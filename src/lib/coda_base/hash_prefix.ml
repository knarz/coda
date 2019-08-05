open Core_kernel
open Hash_prefixes

let length_in_triples = length_in_triples

let salt (s : t) = Snark_params.Tick.Pedersen.(State.salt (s :> string))

let protocol_state = salt protocol_state

let protocol_state_body = salt protocol_state_body

let account = salt account

let merkle_tree =
  Array.init Snark_params.ledger_depth ~f:(fun i -> salt (merkle_tree i))

let proof_of_work = salt proof_of_work

let merge_snark = salt merge_snark

let base_snark = salt base_snark

let transition_system_snark = salt transition_system_snark

let signature = salt signature

let receipt_chain = salt receipt_chain

let epoch_seed = salt epoch_seed

let vrf_message = salt vrf_message

let vrf_output = salt vrf_output

let coinbase_merkle_tree =
  Array.init Snark_params.pending_coinbase_depth ~f:(fun i ->
      salt (coinbase_merkle_tree i) )

let coinbase = salt coinbase

let pending_coinbases = salt pending_coinbases

let coinbase_stack_data = salt coinbase_stack_data

let coinbase_stack_state_hash = salt coinbase_stack_state_hash

let checkpoint_list = salt checkpoint_list
