let key name input = "r:" ^ name ^ " " ^ Json.to_string input
let send : (string -> Json.t -> ((Json.t, Status.error) result -> unit) -> unit -> unit) ref =
  ref (fun _ _ k ->
      k (Error (Status.Network "no action transport"));
      ignore)

let reading : (string -> Json.t -> ((Json.t, Status.error) result -> unit) -> unit -> unit) option ref = ref None

let error (j : Json.t) : Status.error option =
  match j with
  | `Assoc fields -> (
      let text () = match List.assoc_opt "message" fields with Some (`String m) -> m | _ -> "" in
      match List.assoc_opt "kind" fields with
      | Some (`String "rejected") -> Some (Status.Rejected (text ()))
      | Some (`String "forbidden") -> Some Status.Forbidden
      | Some (`String "not_found") -> Some Status.Not_found
      | Some (`String "server") -> Some Status.Server
      | Some (`String "network") -> Some (Status.Network (text ()))
      | Some (`String "protocol") -> Some (Status.Protocol (text ()))
      | _ -> None)
  | _ -> None

let decode el =
  match Json.of_string (Web.text_content el) with
  | Ok (`Assoc [ ("ok", j) ]) -> Some (Ok j)
  | Ok (`Assoc [ ("error", e) ]) -> ( match error e with Some e -> Some (Error e) | None -> None)
  | _ -> None

let answer name input k =
  let key = key name input in
  let mine el = match Web.get_attribute el "data-yuka-answer" with Some a -> String.equal a key | None -> false in
  let full els = Option.bind (List.find_opt (fun el -> mine el && Option.is_none (Web.get_attribute el "data-pending")) els) decode in
  let scripts n = Array.to_list (Web.query_all n "script[data-yuka-answer]") in
  let all = scripts (Web.document ()) in
  match full all with
  | Some r ->
      k r;
      ignore
  | None when String.equal (Web.ready_state ()) "loading" && List.exists mine all ->
      let stop_watch = ref ignore and stop_ready = ref ignore in
      let stop () =
        !stop_watch ();
        !stop_ready ()
      in
      stop_watch :=
        Web.watch_added (fun nodes ->
            match
              full
                (List.concat_map
                   (fun n -> (if String.equal (Web.local_name n) "script" then [ n ] else []) @ scripts n)
                   (Array.to_list nodes))
            with
            | Some r ->
                !stop_ready ();
                k r;
                true
            | None -> false);
      stop_ready :=
        Web.on_dom_ready (fun () ->
            stop ();
            match full (scripts (Web.document ())) with Some r -> k r | None -> stop_ready := !send name input k);
      stop
  | None -> !send name input k
