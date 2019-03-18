// Nav styles adapted from https://medium.com/creative-technology-concepts-code/responsive-mobile-dropdown-navigation-using-css-only-7218e4498a99

module Style = {
  open Css;
  open Style;

  module MediaQuery = {
    let menu = "(min-width: 58rem)";
    let statusLift = "(min-width: 38rem)";
  };

  let item =
    merge([
      style(
        paddingX(`rem(0.75))
        @ paddingY(`rem(1.0))
        @ [listStyle(`none, `inside, `none)],
      ),
    ]);

  let options =
    style([
      // hidden on mobile by default
      display(`none),
      // when it's not hidden, make the dropdown appear
      position(`absolute),
      right(`rem(0.0)),
      top(`rem(2.0)),
      backgroundColor(Colors.white),
      // always visible and flexed on full
      media(
        MediaQuery.menu,
        [
          display(`flex),
          justifyContent(`spaceBetween),
          position(`static),
          width(`percent(100.0)),
        ],
      ),
    ]);

  let menuBtn =
    style([
      display(`none),
      selector({j|:checked ~ .$options|j}, [display(`block)]),
    ]);

  let menuIcon =
    style([
      cursor(`pointer),
      display(`flex),
      justifyContent(`flexEnd),
      position(`relative),
      userSelect(`none),
      // The menu is always shown on full-size
      media(MediaQuery.menu, [display(`none)]),
    ]);

  let menuText =
    merge([
      style([marginLeft(`rem(1.0)), ...paddingY(`rem(1.0))]),
      Link.style,
    ]);

  let nav =
    style([
      display(`flex),
      justifyContent(`spaceBetween),
      alignItems(`center),
      flexWrap(`wrap),
      media(MediaQuery.statusLift, [flexWrap(`nowrap)]),
    ]);
};
open Style;

module Logo = {
  open Css;

  module Placeholder = {
    let style =
      style([
        backgroundColor(`rgb((0, 255, 0))),
        width(`px(116)),
        height(`px(21)),
      ]);
  };
};

module Testnet = {
  open Css;

  module Placeholder = {
    let style =
      style([
        backgroundColor(`rgba((45, 158, 219, 0.1))),
        width(`percent(100.0)),
        height(`px(40)),
        margin(`auto),
        media(MediaQuery.statusLift, [width(`px(341))]),
      ]);
  };
};

let component = ReasonReact.statelessComponent("Nav");
let make = children => {
  ...component,
  render: _self => {
    let items =
      children |> Array.map(elem => <li className=Style.item> elem </li>);

    <nav className=Style.nav>
      <div
        className=Css.(
          style([
            width(`percent(50.0)),
            media(
              MediaQuery.statusLift,
              [width(`auto), marginRight(`rem(0.75))],
            ),
          ])
        )>
        <div className=Logo.Placeholder.style />
      </div>
      <div
        className=Css.(
          style([
            order(3),
            width(`percent(100.0)),
            media(MediaQuery.statusLift, [order(2), width(`auto)]),
            media(MediaQuery.menu, [width(`percent(40.0))]),
          ])
        )>
        <div className=Testnet.Placeholder.style />
      </div>
      <div
        className=Css.(
          style([
            width(`auto),
            order(2),
            media(MediaQuery.statusLift, [order(3), width(`auto)]),
            media(MediaQuery.menu, [width(`percent(50.0))]),
          ])
        )>
        /* we use the input to get a :checked pseudo selector
         * that we can use to get on-click without javascript at runtime */

          <input className=Style.menuBtn type_="checkbox" id="nav-menu-btn" />
          <label className=Style.menuIcon htmlFor="nav-menu-btn">
            <span className=Style.menuText>
              {ReasonReact.string("Menu")}
            </span>
          </label>
          <ul className=Style.options> ...items </ul>
        </div>
    </nav>;
  },
};