type metadata = {
  title: string,
  author: string,
  date: string,
  subtitle: option(string),
  authorWebsite: option(string),
};

let parseMetadata = (content, filename) =>
  Markdown.{
    title: Metadata.getRequiredValue("title", content, filename),
    author: Metadata.getRequiredValue("author", content, filename),
    date: Metadata.getRequiredValue("date", content, filename),
    subtitle: Metadata.getValue("subtitle", content),
    authorWebsite: Metadata.getValue("author_website", content),
  };

module Comments = {
  let component = ReasonReact.statelessComponent("BlogPost.Comments");
  let make = (~name, _) => {
    ...component,
    render: _self =>
      <div>
        <div id="disqus_thread" className="mw65 center" />
        <RunScript>
          {Printf.sprintf(
             {|
var disqus_config = function () {
  this.page.url = "https://codaprotocol.com/blog/%s.html";
  this.page.identifier = "codaprotocol/blog/%s?1";
};
(function() {
  var d = document, s = d.createElement('script');
  s.src = 'https://codaprotocol-com.disqus.com/embed.js';
  s.setAttribute('data-timestamp', +new Date());
  (d.head || d.body).appendChild(s);
})();
|},
             name,
             name,
           )}
        </RunScript>
        <noscript>
          {ReasonReact.string("Please enable JavaScript to view the ")}
          <a href="https://disqus.com/?ref_noscript">
            {ReasonReact.string("comments powered by Disqus.")}
          </a>
        </noscript>
      </div>,
  };
};

module MailingList = {
  let component = ReasonReact.statelessComponent("BlogPost.MailingList");
  let make = _ => {
    ...component,
    render: _self =>
      <a
        href="https://goo.gl/forms/PTusW11oYpLKJrZH3"
        className="user-select-none hover-bg-black white no-underline ttu tracked bg-silver icon-shadow ph3 pv3 br4 tc lh-copy f5 bottomrightfixed br--top"
        name="fixed"
        target="_blank">
        {ReasonReact.string("Join mailing list")}
      </a>,
  };
};

let dot = {
  ReasonReact.string({js|•|js});
};

let shareItems =
  <>
    <span className="f7 ttu fw4 ddinexp tracked-mega blueshare">
      {ReasonReact.string("share:")}
    </span>
    <a href="https://twitter.com/codaprotocol">
      {ReasonReact.string("Twitter")}
    </a>
    dot
    <a href="https://discord.gg/UyqY37F"> {ReasonReact.string("Discord")} </a>
    dot
    <a href="https://t.me/codaprotocol"> {ReasonReact.string("Telegram")} </a>
    dot
    <a href="https://news.ycombinator.com/item?id=18726110">
      {ReasonReact.string("Hacker News")}
    </a>
  </>;

let component = ReasonReact.statelessComponent("BlogPost");

let extraHeaders =
  <>
    <link
      rel="stylesheet"
      href="https://cdn.jsdelivr.net/npm/katex@0.10.0/dist/katex.min.css"
      integrity="sha384-9eLZqc9ds8eNjO3TmqPeYcDj8n+Qfa4nuSiGYa6DjLNcv9BtN69ZIulL9+8CqC9Y"
      crossOrigin="anonymous"
    />
    <script
      defer=true
      src="https://cdn.jsdelivr.net/npm/katex@0.10.0/dist/katex.min.js"
      integrity="sha384-K3vbOmF2BtaVai+Qk37uypf7VrgBubhQreNQe9aGsz9lB63dIFiQVlJbr92dw2Lx"
      crossOrigin="anonymous"
    />
    <script
      defer=true
      src="https://cdn.jsdelivr.net/npm/katex@0.10.0/dist/contrib/auto-render.min.js"
      integrity="sha384-kmZOZB5ObwgQnS/DuDg6TScgOiWWBiVt0plIRkZCmE6rDZGrEOQeHM5PcHi+nyqe"
      crossOrigin="anonymous"
    />
    <link rel="stylesheet" href="/static/css/blog.css" />
  </>;

let make = (~name, ~html, ~metadata, ~showComments=true, _) => {
  {
    ...component,
    render: _self =>
      <div>
        <div className="ph3 ph4-m ph5-l">
          <div>
            <div className="db dn-l">
              <div className="mw65-ns ibmplex f5 center blueblack">
                <a
                  href={"/blog/" ++ name ++ ".html"}
                  className="blueblack no-underline hover-link">
                  <h1
                    className="f2 f1-ns ddinexp tracked-tightish pt2 pt3-m pt4-l mb1"
                    dangerouslySetInnerHTML={"__html": metadata.title}
                  />
                </a>
                {switch (metadata.subtitle) {
                 | None => <div className="mt0 mb4" />
                 | Some(subtitle) =>
                   <h2
                     className="f4 f3-ns ddinexp mt0 mb4 fw4"
                     dangerouslySetInnerHTML={"__html": subtitle}
                   />
                 }}
                <h4
                  className="f7 fw4 tracked-supermega ttu metropolis mt0 mb1">
                  {switch (metadata.authorWebsite) {
                   | None =>
                     <span className="mr2">
                       {ReasonReact.string("by " ++ metadata.author ++ " ")}
                     </span>
                   | Some(website) =>
                     <a
                       href=website
                       className="blueblack no-underline"
                       target="_blank">
                       <span className="mr2">
                         {ReasonReact.string("by " ++ metadata.author ++ " ")}
                       </span>
                       <i
                         className="ml-1 ml-2-ns fab f7 fa-twitter mr3 mr2-m mr3-l"
                       />
                     </a>
                   }}
                </h4>
                <h4
                  className="f7 fw4 tracked-supermega ttu o-50 metropolis mt0 mb45">
                  {ReasonReact.string(metadata.date)}
                </h4>
                <div className="blog-content lh-copy">
                  <div dangerouslySetInnerHTML={"__html": html} /> // TODO: replace this with some react markdown component
                  <hr />
                </div>
                <div className="share flex justify-center items-center mb4">
                  shareItems
                </div>
              </div>
            </div>
            <div className="db-l dn">
              <div className="mw7 center ibmplex blueblack side-footnotes">
                <div className="mw65-ns f5 left blueblack">
                  <a
                    href={"/blog/" ++ name ++ ".html"}
                    className="blueblack no-underline hover-link">
                    <h1
                      className="f2 f1-ns ddinexp tracked-tightish pt2 pt3-m pt4-l mb1"
                      dangerouslySetInnerHTML={"__html": metadata.title}
                    />
                  </a>
                  {switch (metadata.subtitle) {
                   | None => <div className="mt0 mb4" />
                   | Some(subtitle) =>
                     <h2
                       className="f4 f3-ns ddinexp mt0 mb4 fw4"
                       dangerouslySetInnerHTML={"__html": subtitle}
                     />
                   }}
                  <h4
                    className="f7 fw4 tracked-supermega ttu metropolis mt0 mb1">
                    {switch (metadata.authorWebsite) {
                     | None =>
                       <span className="mr2">
                         {ReasonReact.string("by " ++ metadata.author ++ " ")}
                       </span>
                     | Some(website) =>
                       <a
                         href=website
                         className="blueblack no-underline"
                         target="_blank">
                         <span className="mr2">
                           {ReasonReact.string(
                              "by " ++ metadata.author ++ " ",
                            )}
                         </span>
                         <i
                           className="ml-1 ml-2-ns fab f7 fa-twitter mr3 mr2-m mr3-l"
                         />
                       </a>
                     }}
                  </h4>
                  <h4
                    className="f7 fw4 tracked-supermega ttu o-50 metropolis mt0 mb45">
                    {ReasonReact.string(metadata.date)}
                  </h4>
                  <div className="blog-content lh-copy">
                    <div dangerouslySetInnerHTML={"__html": html} /> // TODO: replace this with some react markdown component
                    <hr />
                  </div>
                  <div className="share flex justify-center items-center mb4">
                    shareItems
                  </div>
                </div>
              </div>
            </div>
            {showComments ? <Comments name /> : ReasonReact.null}
          </div>
        </div>
        <MailingList />
        <RunScript>
          {|
          document.addEventListener("DOMContentLoaded", function() {
            renderMathInElement(document.body);

            var blocks = document.querySelectorAll(".katex-block code");
            for (var i = 0; i < blocks.length; i++) {
              var b = blocks[i];
              katex.render(b.innerText, b, {displayMode:true});
            }

            var blocks = document.querySelectorAll(".blog-content a");
            for (var i = 0; i < blocks.length; i++) {
              var b = blocks[i];
              if (b.href.indexOf('#') === -1) {
                b.target = '_blank';
              }
            }
          });|}
        </RunScript>
      </div>,
  };
};