[@bs.module "emotion-server"]
external renderStylesToString: string => string = "";

type critical = {
  .
  "html": string,
  "css": string,
};

[@bs.module "emotion-server"]
external extractCritical: string => critical = "";

module Fs = {
  [@bs.val] [@bs.module "fs"]
  external mkdirSync:
    (
      string,
      {
        .
        "recursive": bool,
        "mode": int,
      }
    ) =>
    unit =
    "";

  [@bs.val] [@bs.module "fs"]
  external symlinkSync: (string, string) => unit = "";
};

module Rimraf = {
  [@bs.val] [@bs.module "rimraf"] external sync: string => unit = "";
};

Links.Cdn.setPrefix(
  Config.isProd ? "https://cdn.codaprotocol.com/website" : "",
);

Style.Typeface.load();

let writeStatic = (path, rootComponent) => {
  let rendered =
    extractCritical(ReactDOMServerRe.renderToStaticMarkup(rootComponent));
  Node.Fs.writeFileAsUtf8Sync(
    path ++ ".html",
    "<!doctype html>\n" ++ rendered##html,
  );
  Node.Fs.writeFileAsUtf8Sync(path ++ ".css", rendered##css);
};

let asset_regex = [%re {|/\/static\/blog\/.*{png,jpg,svg}/|}];

let posts = {
  let unsorted =
    Node.Fs.readdirSync("posts")
    |> Array.to_list
    |> List.filter(s => Js.String.endsWith(Markdown.suffix, s))
    |> List.map(fileName => {
         let length =
           String.length(fileName) - String.length(Markdown.suffix);
         let name = String.sub(fileName, 0, length);
         let path = "posts/" ++ fileName;
         let (html, content) = Markdown.load(path);
         let metadata = BlogPost.parseMetadata(content, path);
         (name, html, metadata);
       });

  List.sort(
    ((_, _, metadata1), (_, _, metadata2)) => {
      let date1 = Js.Date.fromString(metadata1.BlogPost.date);
      let date2 = Js.Date.fromString(metadata2.date);
      let diff = Js.Date.getTime(date2) -. Js.Date.getTime(date1);
      if (diff > 0.) {
        1;
      } else if (diff < 0.) {
        (-1);
      } else {
        0;
      };
    },
    unsorted,
  );
};

module Router = {
  type t =
    | File(string, ReasonReact.reactElement)
    | Dir(string, array(t));

  let generateStatic = {
    let rec helper = path =>
      fun
      | File(name, elem) => {
          writeStatic(path ++ "/" ++ name, elem);
        }
      | Dir(name, routes) => {
          let path_ = path ++ "/" ++ name;
          Fs.mkdirSync(path_, {"recursive": true, "mode": 0o755});
          routes |> Array.iter(helper(path_));
        };

    helper("./");
  };
};

let jobOpenings = [|
  ("engineering-manager", "Engineering Manager (San Francisco)."),
  ("product-manager", "Product Manager (San Francisco)."),
  ("senior-designer", "Senior Designer (San Francisco)."),
  (
    "senior-frontend-engineer",
    "Senior Product Engineer (Frontend) (San Francisco).",
  ),
  ("frontend-engineer", "Product Engineer (Frontend) (San Francisco)."),
  ("fullstack-engineer", "Product Engineer (Full-stack) (San Francisco)."),
  (
    "marketing-and-communications-manager",
    "Marketing and Communications Manager (San Francisco).",
  ),
  ("protocol-engineer", "Senior Protocol Engineer (San Francisco)."),
|];

// GENERATE

Rimraf.sync("site");

let blogPage = name =>
  <Page page=`Blog name extraHeaders={Blog.extraHeaders()}>
    <Wrapped> <Blog posts /> </Wrapped>
  </Page>;

Router.(
  generateStatic(
    Dir(
      "site",
      [|
        File(
          "index",
          <Page page=`Home name="index" footerColor=Style.Colors.navyBlue>
            <Home
              posts={List.map(
                ((name, html, metadata)) =>
                  (name, html, (metadata.BlogPost.title, "blog-" ++ name)),
                posts,
              )}
            />
          </Page>,
        ),
        Dir(
          "blog",
          posts
          |> Array.of_list
          |> Array.map(((name, html, metadata)) =>
               File(
                 name,
                 <Page
                   page=`Blog
                   name
                   extraHeaders={Blog.extraHeaders()}
                   footerColor=Style.Colors.gandalf>
                   <Wrapped> <BlogPost name html metadata /> </Wrapped>
                 </Page>,
               )
             )
          |> Array.append([|File("index", blogPage("index"))|]),
        ),
        Dir(
          "jobs",
          jobOpenings
          |> Array.map(((name, _)) =>
               File(
                 name,
                 <Page
                   page=`Jobs
                   name
                   footerColor=Style.Colors.gandalf
                   extraHeaders={CareerPost.extraHeaders()}>
                   <Wrapped>
                     <CareerPost path={"jobs/" ++ name ++ ".markdown"} />
                   </Wrapped>
                 </Page>,
               )
             ),
        ),
        File(
          "jobs",
          <Page page=`Jobs name="jobs" extraHeaders={Careers.extraHeaders()}>
            <Wrapped> <Careers jobOpenings /> </Wrapped>
          </Page>,
        ),
        File("blog", blogPage("blog")),
        File(
          "privacy",
          <Page page=`Privacy name="privacy">
            <RawHtml path="html/Privacy.html" />
          </Page>,
        ),
        File(
          "tos",
          <Page page=`Tos name="tos"> <RawHtml path="html/TOS.html" /> </Page>,
        ),
      |],
    ),
  )
);

Rimraf.sync("docs-theme");
Router.(
  generateStatic(
    Dir(
      "docs-theme",
      [|
        File(
          "main",
          <Page page=`Docs name="/docs/main">
            <Wrapped> <Docs /> </Wrapped>
          </Page>,
        ),
      |],
    ),
  )
);

module MoreFs = {
  type stat;
  [@bs.val] [@bs.module "fs"] external lstatSync: string => stat = "";
  [@bs.send] external isDirectory: stat => bool = "";

  [@bs.val] [@bs.module "fs"]
  external copyFileSync: (string, string) => unit = "";

  [@bs.val] [@bs.module "fs"] external mkdirSync: string => unit = "";
};

let ignoreFiles = ["main.bc.js", "verifier_main.bc.js", ".DS_Store"];
let rec copyFolder = path => {
  MoreFs.mkdirSync("site/" ++ path);
  Array.iter(
    s => {
      let path = Filename.concat(path, s);
      let isDir = MoreFs.lstatSync(path) |> MoreFs.isDirectory;
      if (isDir) {
        copyFolder(path);
      } else if (!List.mem(s, ignoreFiles)) {
        MoreFs.copyFileSync(
          path,
          "./site" ++ Links.Cdn.getHashedPath("/" ++ path),
        );
      };
    },
    Node.Fs.readdirSync(path),
  );
};

let moveToSite = path =>
  MoreFs.copyFileSync(path, Filename.concat("./site", path));

copyFolder("static");

// Special-case the jsoo-compiled files for now
// They can't be loaded from cdn so they get copied to the site separately
if (!Config.isProd) {
  moveToSite("static/main.bc.js");
  moveToSite("static/verifier_main.bc.js");
};

// Run mkdocs to generate static docs site
Markdown.Child_process.execSync(
  "mkdocs build -d site/docs",
  Markdown.Child_process.option(),
);

Fs.symlinkSync(Node.Process.cwd() ++ "/graphql-docs", "./site/docs/graphql");
