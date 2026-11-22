let script =
  {js|<script>(function(){var root=document.documentElement;function get(key){try{return localStorage.getItem(key)}catch(error){return null}}function put(key,value){try{localStorage.setItem(key,value)}catch(error){}}function valid(zone){try{new Intl.DateTimeFormat("en-US",{timeZone:zone});return true}catch(error){return false}}var theme=get("async-feed-theme");if(theme!=="light"&&theme!=="dark")theme=matchMedia("(prefers-color-scheme: dark)").matches?"dark":"light";root.setAttribute("data-theme",theme);var zone=get("async-feed-zone");if(!zone||!valid(zone))zone=Intl.DateTimeFormat().resolvedOptions().timeZone||"UTC";var short,long,numeric;function formats(){short=new Intl.DateTimeFormat("en-US",{timeZone:zone,year:"numeric",month:"short",day:"numeric",hour:"2-digit",minute:"2-digit",second:"2-digit",hourCycle:"h23",timeZoneName:"short"});long=new Intl.DateTimeFormat("en-US",{timeZone:zone,dateStyle:"full",timeStyle:"long"});numeric=new Intl.DateTimeFormat("en-US",{timeZone:zone,year:"numeric",month:"numeric",day:"numeric",hour:"numeric",minute:"numeric",second:"numeric",hourCycle:"h23"})}formats();function format(element){var date=new Date(Number(element.getAttribute("data-ts"))*1000),text=short.format(date),title=long.format(date)+" ("+zone+")";if(element.textContent!==text)element.textContent=text;if(element.title!==title)element.title=title}function scan(node){if(node.nodeType===3){var parent=node.parentNode;if(parent&&parent.nodeType===1&&parent.hasAttribute("data-ts"))format(parent);return}if(node.nodeType!==1)return;if(node.hasAttribute("data-ts"))format(node);var list=node.querySelectorAll("[data-ts]");for(var i=0;i<list.length;i++)format(list[i])}new MutationObserver(function(records){for(var i=0;i<records.length;i++){var added=records[i].addedNodes;for(var j=0;j<added.length;j++)scan(added[j])}}).observe(root,{childList:true,subtree:true});function wall(time){var parts={};numeric.formatToParts(new Date(time)).forEach(function(part){parts[part.type]=part.value});return Date.UTC(+parts.year,+parts.month-1,+parts.day,+parts.hour,+parts.minute,+parts.second)}window.asyncFeed={zone:function(){return zone},setZone:function(next){if(!valid(next))return;zone=next;put("async-feed-zone",next);formats();if(document.body)scan(document.body)},theme:function(){return root.getAttribute("data-theme")},setTheme:function(next){root.setAttribute("data-theme",next);put("async-feed-theme",next)},toTime:function(value){var match=/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(value);if(!match)return 0;var guess=Date.UTC(+match[1],+match[2]-1,+match[3],+match[4],+match[5]),time=guess-(wall(guess)-guess);time=time-(wall(time)-guess);return Math.floor(time/1000)}}})()</script>|js}

let head base =
  {|<meta name="viewport" content="width=device-width, initial-scale=1"><link rel="icon" type="image/svg+xml" href="|}
  ^ base ^ {|/static/favicon.svg">|} ^ script

let read path = In_channel.with_open_bin path In_channel.input_all

let packages dir =
  match Sys.readdir (Filename.concat dir "node_modules") with
  | names ->
      Array.sort compare names;
      Array.to_list names
  | exception Sys_error _ -> []

type t = { config : Yuka.Server.config; handler : Dream.handler }

let assets ~bundle ~client =
  let js_dir = Filename.concat client "out" in
  match read (Filename.concat client "yuka_islands.json") with
  | exception Sys_error message -> Error message
  | manifest when bundle -> (
      match read (Filename.concat client "meta.json") with
      | exception Sys_error message -> Error message
      | metafile ->
          Yuka.Server.bundle ~dir:(Filename.concat js_dir "demo/async-feed/client") ~entry:"bundle/main.js" ~manifest
            ~metafile)
  | manifest ->
      Yuka.Server.modules ~dir:js_dir ~entry:"demo/async-feed/client/main.js" ~manifest ~packages:(packages js_dir)
        ~digest:(Yuka.Server.tree_digest js_dir)

let make ?(base = "") ?(bundle = false) ?(dev = false) ~dir ~secret () =
  Result.bind (assets ~bundle ~client:(Filename.concat dir "client")) (fun assets ->
      match
        Yuka.Server.config ~base ~assets
          ~public:[ ("/static", Filename.concat dir "static") ]
          ~head:(head base)
          ~styles:[ base ^ "/static/style.css" ]
          ~dev ()
      with
      | exception Invalid_argument message -> Error message
      | config ->
          Handlers.register ();
          Ok { config; handler = Dream.set_secret secret @@ Dream.cookie_sessions @@ Yuka_dream.handler config Yuka_routes.app })
