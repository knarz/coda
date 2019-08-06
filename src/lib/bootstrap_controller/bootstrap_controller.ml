open Core
open Async
open Coda_base
open Coda_state
open Pipe_lib.Strict_pipe

module type Inputs_intf = sig
  include Transition_frontier.Inputs_intf

  module Transition_frontier :
    Coda_intf.Transition_frontier_intf
    with type external_transition_validated := External_transition.Validated.t
     and type mostly_validated_external_transition :=
                ( [`Time_received] * Truth.true_t
                , [`Proof] * Truth.true_t
                , [`Frontier_dependencies] * Truth.true_t
                , [`Staged_ledger_diff] * Truth.false_t )
                External_transition.Validation.with_transition
     and type transaction_snark_scan_state := Staged_ledger.Scan_state.t
     and type staged_ledger_diff := Staged_ledger_diff.t
     and type staged_ledger := Staged_ledger.t
     and type verifier := Verifier.t

  module Root_sync_ledger :
    Syncable_ledger.S
    with type addr := Ledger.Location.Addr.t
     and type hash := Ledger_hash.t
     and type root_hash := Ledger_hash.t
     and type merkle_tree := Ledger.Db.t
     and type account := Account.t
     and type merkle_path := Ledger.path
     and type query := Sync_ledger.Query.t
     and type answer := Sync_ledger.Answer.t

  module Network :
    Coda_intf.Network_intf
    with type external_transition := External_transition.t
     and type transaction_snark_scan_state := Staged_ledger.Scan_state.t

  module Sync_handler :
    Coda_intf.Sync_handler_intf
    with type external_transition := External_transition.t
     and type external_transition_validated := External_transition.Validated.t
     and type transition_frontier := Transition_frontier.t
     and type parallel_scan_state := Staged_ledger.Scan_state.t

  module Root_prover :
    Coda_intf.Root_prover_intf
    with type transition_frontier := Transition_frontier.t
     and type external_transition := External_transition.t
     and type external_transition_with_initial_validation :=
                External_transition.with_initial_validation
     and type verifier := Verifier.t
end

module Make (Inputs : Inputs_intf) : sig
  open Inputs

  include
    Coda_intf.Bootstrap_controller_intf
    with type network := Network.t
     and type verifier := Verifier.t
     and type transition_frontier := Transition_frontier.t
     and type external_transition_with_initial_validation :=
                External_transition.with_initial_validation

  module For_tests : sig
    type t

    val make_bootstrap :
         logger:Logger.t
      -> trust_system:Trust_system.t
      -> verifier:Verifier.t
      -> genesis_root:External_transition.Validated.t
      -> network:Network.t
      -> t

    val on_transition :
         t
      -> sender:Unix.Inet_addr.t
      -> root_sync_ledger:( State_hash.t
                          * Unix.Inet_addr.t
                          * Staged_ledger_hash.t )
                          Root_sync_ledger.t
      -> External_transition.t
      -> [> `Syncing_new_snarked_ledger | `Updating_root_transition | `Ignored]
         Deferred.t

    module Transition_cache :
      Transition_cache.S
      with type external_transition_with_initial_validation :=
                  External_transition.with_initial_validation
       and type state_hash := State_hash.t

    val sync_ledger :
         t
      -> root_sync_ledger:( State_hash.t
                          * Unix.Inet_addr.t
                          * Staged_ledger_hash.t )
                          Root_sync_ledger.t
      -> transition_graph:Transition_cache.t
      -> sync_ledger_reader:( [< `Transition of
                                 External_transition.with_initial_validation
                                 Envelope.Incoming.t ]
                            * [< `Time_received of 'a] )
                            Pipe_lib.Strict_pipe.Reader.t
      -> unit Deferred.t
  end
end = struct
  open Inputs

  type t =
    { logger: Logger.t
    ; trust_system: Trust_system.t
    ; verifier: Verifier.t
    ; mutable best_seen_transition: External_transition.with_initial_validation
    ; mutable current_root: External_transition.with_initial_validation
    ; network: Network.t }

  module Transition_cache = Transition_cache.Make (Inputs)

  let worth_getting_root t candidate =
    `Take
    = Consensus.Hooks.select
        ~logger:
          (Logger.extend t.logger
             [ ( "selection_context"
               , `String "Bootstrap_controller.worth_getting_root" ) ])
        ~existing:
          ( t.best_seen_transition |> fst |> With_hash.data
          |> External_transition.protocol_state
          |> Protocol_state.consensus_state )
        ~candidate

  let received_bad_proof t sender_host e =
    Trust_system.(
      record t.trust_system t.logger sender_host
        Actions.
          ( Violated_protocol
          , Some
              ( "Bad ancestor proof: $error"
              , [("error", `String (Error.to_string_hum e))] ) ))

  let done_syncing_root root_sync_ledger =
    Option.is_some (Root_sync_ledger.peek_valid_tree root_sync_ledger)

  let on_transition t ~sender ~root_sync_ledger
      (candidate_transition : External_transition.t) =
    let candidate_state =
      External_transition.protocol_state candidate_transition
      |> Protocol_state.consensus_state
    in
    if
      done_syncing_root root_sync_ledger
      || (not @@ worth_getting_root t candidate_state)
    then Deferred.return `Ignored
    else
      match%bind Network.get_ancestry t.network sender candidate_state with
      | Error e ->
          Deferred.return
          @@ Fn.const `Ignored
          @@ Logger.error t.logger ~module_:__MODULE__ ~location:__LOC__
               ~metadata:[("error", `String (Error.to_string_hum e))]
               !"Could not get the proof of the root transition from the \
                 network: $error"
      | Ok peer_root_with_proof -> (
          match%bind
            Root_prover.verify ~logger:t.logger ~verifier:t.verifier
              ~observed_state:candidate_state ~peer_root:peer_root_with_proof
          with
          | Ok (peer_root, peer_best_tip) -> (
              let%bind () =
                Trust_system.(
                  record t.trust_system t.logger sender
                    Actions.
                      ( Fulfilled_request
                      , Some ("Received verified peer root and best tip", [])
                      ))
              in
              t.best_seen_transition <- peer_best_tip ;
              t.current_root <- peer_root ;
              let blockchain_state =
                t.current_root |> fst |> With_hash.data
                |> External_transition.protocol_state
                |> Protocol_state.blockchain_state
              in
              let expected_staged_ledger_hash =
                blockchain_state |> Blockchain_state.staged_ledger_hash
              in
              let snarked_ledger_hash =
                blockchain_state |> Blockchain_state.snarked_ledger_hash
              in
              return
              @@
              match
                Root_sync_ledger.new_goal root_sync_ledger
                  (Frozen_ledger_hash.to_ledger_hash snarked_ledger_hash)
                  ~data:
                    ( With_hash.hash (fst t.current_root)
                    , sender
                    , expected_staged_ledger_hash )
                  ~equal:(fun (hash1, _, _) (hash2, _, _) ->
                    State_hash.equal hash1 hash2 )
              with
              | `New ->
                  `Syncing_new_snarked_ledger
              | `Update_data ->
                  `Updating_root_transition
              | `Repeat ->
                  `Ignored )
          | Error e ->
              return (received_bad_proof t sender e |> Fn.const `Ignored) )

  let sync_ledger t ~root_sync_ledger ~transition_graph ~sync_ledger_reader =
    let query_reader = Root_sync_ledger.query_reader root_sync_ledger in
    let response_writer = Root_sync_ledger.answer_writer root_sync_ledger in
    Network.glue_sync_ledger t.network query_reader response_writer ;
    Reader.iter sync_ledger_reader
      ~f:(fun (`Transition incoming_transition, `Time_received _) ->
        let ({With_hash.data= transition; hash= _}, _)
              : External_transition.with_initial_validation =
          Envelope.Incoming.data incoming_transition
        in
        let sender =
          match Envelope.Incoming.sender incoming_transition with
          | Envelope.Sender.Local ->
              failwith
                "Unexpected, we should be syncing only to remote nodes in \
                 sync ledger"
          | Envelope.Sender.Remote inet_addr ->
              inet_addr
        in
        let protocol_state = External_transition.protocol_state transition in
        let previous_state_hash =
          Protocol_state.previous_state_hash protocol_state
        in
        Transition_cache.add transition_graph ~parent:previous_state_hash
          incoming_transition ;
        (* TODO: Efficiently limiting the number of green threads in #1337 *)
        if worth_getting_root t (Protocol_state.consensus_state protocol_state)
        then
          Deferred.ignore
          @@ on_transition t ~sender ~root_sync_ledger transition
        else Deferred.unit )

  let rec run ~logger ~trust_system ~verifier ~network ~frontier ~ledger_db
      ~transition_reader =
    let sync_ledger_reader, sync_ledger_writer =
      create ~name:"sync ledger pipe"
        (Buffered (`Capacity 50, `Overflow Crash))
    in
    transfer_while_writer_alive transition_reader sync_ledger_writer ~f:Fn.id
    |> don't_wait_for ;
    let initial_breadcrumb = Transition_frontier.root frontier in
    let initial_root_transition =
      External_transition.Validation.lower
        (Transition_frontier.Breadcrumb.transition_with_hash initial_breadcrumb)
        ( (`Time_received, Truth.True)
        , (`Proof, Truth.True)
        , (`Frontier_dependencies, Truth.False)
        , (`Staged_ledger_diff, Truth.False) )
    in
    let t =
      { network
      ; logger
      ; trust_system
      ; verifier
      ; best_seen_transition= initial_root_transition
      ; current_root= initial_root_transition }
    in
    let transition_graph = Transition_cache.create () in
    let%bind synced_db, (hash, sender, expected_staged_ledger_hash) =
      let root_sync_ledger =
        Root_sync_ledger.create ledger_db ~logger:t.logger ~trust_system
      in
      sync_ledger t ~root_sync_ledger ~transition_graph ~sync_ledger_reader
      |> don't_wait_for ;
      let%map synced_db, root_data =
        Root_sync_ledger.valid_tree root_sync_ledger
      in
      Root_sync_ledger.destroy root_sync_ledger ;
      (synced_db, root_data)
    in
    assert (
      Ledger.Db.(
        Ledger_hash.equal (merkle_root ledger_db) (merkle_root synced_db)) ) ;
    match%bind
      let open Deferred.Or_error.Let_syntax in
      let%bind scan_state, expected_merkle_root, pending_coinbases =
        Network.get_staged_ledger_aux_and_pending_coinbases_at_hash t.network
          sender hash
      in
      let received_staged_ledger_hash =
        Staged_ledger_hash.of_aux_ledger_and_coinbase_hash
          (Staged_ledger.Scan_state.hash scan_state)
          expected_merkle_root pending_coinbases
      in
      let%bind () =
        Staged_ledger_hash.equal expected_staged_ledger_hash
          received_staged_ledger_hash
        |> Result.ok_if_true
             ~error:(Error.of_string "received faulty scan state from peer")
        |> Deferred.return
      in
      Staged_ledger.of_scan_state_pending_coinbases_and_snarked_ledger ~logger
        ~verifier ~scan_state
        ~snarked_ledger:(Ledger.of_database synced_db)
        ~expected_merkle_root ~pending_coinbases
    with
    | Error e ->
        let%bind () =
          Trust_system.(
            record t.trust_system t.logger sender
              Actions.
                ( Violated_protocol
                , Some
                    ( "Can't find scan state from the peer or received faulty \
                       scan state from the peer."
                    , [] ) ))
        in
        Logger.error logger ~module_:__MODULE__ ~location:__LOC__
          ~metadata:
            [ ("error", `String (Error.to_string_hum e))
            ; ("state_hash", State_hash.to_yojson hash) ]
          "Failed to find scan state for the transition with hash $state_hash \
           from the peer or received faulty scan state: $error. Retry \
           bootstrap" ;
        Writer.close sync_ledger_writer ;
        run ~logger ~trust_system ~verifier ~network ~frontier ~ledger_db
          ~transition_reader
    | Ok root_staged_ledger -> (
        let%bind () =
          Trust_system.(
            record t.trust_system t.logger sender
              Actions.
                ( Fulfilled_request
                , Some ("Received valid scan state from peer", []) ))
        in
        let new_root =
          With_hash.map (fst t.current_root) ~f:(fun root ->
              (* TODO: review the correctness of this action #2480 *)
              let (`I_swear_this_is_safe_see_my_comment root') =
                External_transition.Validated.create_unsafe root
              in
              root' )
        in
        let consensus_state =
          With_hash.data new_root
          |> External_transition.Validated.protocol_state
          |> Protocol_state.consensus_state
        in
        let local_state = Transition_frontier.consensus_local_state frontier in
        match%bind
          match
            Consensus.Hooks.required_local_state_sync ~consensus_state
              ~local_state
          with
          | None ->
              Logger.debug logger ~module_:__MODULE__ ~location:__LOC__
                ~metadata:
                  [ ( "local_state"
                    , Consensus.Data.Local_state.to_yojson local_state )
                  ; ( "consensus_state"
                    , Consensus.Data.Consensus_state.Value.to_yojson
                        consensus_state ) ]
                "Not synchronizing consensus local state" ;
              Deferred.return @@ Ok ()
          | Some sync_jobs ->
              Logger.info logger ~module_:__MODULE__ ~location:__LOC__
                "Synchronizing consensus local state" ;
              Consensus.Hooks.sync_local_state ~local_state ~logger
                ~trust_system
                ~random_peers:(fun n ->
                  List.append
                    (Network.peers_by_ip t.network sender)
                    (Network.random_peers t.network n) )
                ~query_peer:
                  { Network_peer.query=
                      (fun peer f query ->
                        Network.query_peer t.network peer f query ) }
                sync_jobs
        with
        | Error e ->
            Logger.error logger ~module_:__MODULE__ ~location:__LOC__
              ~metadata:[("error", `String (Error.to_string_hum e))]
              "Local state sync failed: $error. Retry bootstrap" ;
            Writer.close sync_ledger_writer ;
            run ~logger ~trust_system ~verifier ~network ~frontier ~ledger_db
              ~transition_reader
        | Ok () ->
            let%map new_frontier =
              Transition_frontier.create ~logger ~root_transition:new_root
                ~root_snarked_ledger:synced_db ~root_staged_ledger
                ~consensus_local_state:local_state
            in
            Logger.info logger ~module_:__MODULE__ ~location:__LOC__
              "Bootstrap state: complete." ;
            (new_frontier, Transition_cache.data transition_graph) )

  module For_tests = struct
    type nonrec t = t

    let make_bootstrap ~logger ~trust_system ~verifier ~genesis_root ~network =
      let transition_with_hash =
        With_hash.of_data genesis_root
          ~hash_data:
            (Fn.compose Protocol_state.hash
               External_transition.Validated.protocol_state)
      in
      let transition =
        External_transition.Validation.lower transition_with_hash
          ( (`Time_received, Truth.True)
          , (`Proof, Truth.True)
          , (`Frontier_dependencies, Truth.False)
          , (`Staged_ledger_diff, Truth.False) )
      in
      { logger
      ; trust_system
      ; verifier
      ; best_seen_transition= transition
      ; current_root= transition
      ; network }

    let on_transition = on_transition

    module Transition_cache = Transition_cache

    let sync_ledger = sync_ledger
  end
end

include Make (struct
  include Transition_frontier.Inputs
  module Transition_frontier = Transition_frontier
  module Root_sync_ledger = Sync_ledger.Db
  module Network = Coda_networking
  module Sync_handler = Sync_handler
  module Root_prover = Root_prover
end)
