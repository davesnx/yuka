module Buffer = Stdlib.Buffer

type t = {
  title : string option;
  description : string option;
  canonical : string option;
  robots : string option;
  og : (string * string) list;
  twitter : (string * string) list;
  alternates : (string * string) list;
  json_ld : Json.t list;
}

let empty =
  { title = None; description = None; canonical = None; robots = None; og = []; twitter = []; alternates = []; json_ld = [] }

let make ?title ?description ?canonical ?robots ?(og = []) ?(twitter = []) ?(alternates = []) ?(json_ld = []) () =
  { title; description; canonical; robots; og; twitter; alternates; json_ld }

let pick outer inner = match inner with Some _ -> inner | None -> outer

let pairs outer inner =
  List.filter (fun (k, _) -> not (List.exists (fun (k', _) -> String.equal k k') inner)) outer @ inner

let merge o i =
  {
    title = pick o.title i.title;
    description = pick o.description i.description;
    canonical = pick o.canonical i.canonical;
    robots = pick o.robots i.robots;
    og = pairs o.og i.og;
    twitter = pairs o.twitter i.twitter;
    alternates = pairs o.alternates i.alternates;
    json_ld = o.json_ld @ i.json_ld;
  }

let to_html h =
  let b = Buffer.create 64 in
  let tag name attrs =
    Buffer.add_char b '<';
    Buffer.add_string b name;
    List.iter (fun (n, v) -> Printer.add_attr b ~tag:name n v) attrs;
    Buffer.add_string b " data-yuka-head>"
  in
  let meta key name value = tag "meta" [ (key, name); ("content", value) ] in
  Option.iter (meta "name" "description") h.description;
  Option.iter (meta "name" "robots") h.robots;
  Option.iter (fun href -> tag "link" [ ("rel", "canonical"); ("href", href) ]) h.canonical;
  List.iter
    (fun (lang, href) -> tag "link" [ ("rel", "alternate"); ("hreflang", lang); ("href", href) ])
    h.alternates;
  List.iter (fun (k, v) -> meta "property" ("og:" ^ k) v) h.og;
  List.iter (fun (k, v) -> meta "name" ("twitter:" ^ k) v) h.twitter;
  List.iter
    (fun j ->
      tag "script" [ ("type", "application/ld+json") ];
      Buffer.add_string b (Json.to_string j);
      Buffer.add_string b "</script>")
    h.json_ld;
  Buffer.contents b
