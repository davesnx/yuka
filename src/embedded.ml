let key name input = "r:" ^ name ^ " " ^ Json.to_string input
let reading : (string -> Json.t -> (Json.t, Status.error) result option) option ref = ref None

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

let answer name input =
  let key = key name input in
  let full el =
    Option.is_none (Web.get_attribute el "data-pending")
    && match Web.get_attribute el "data-yuka-answer" with Some k -> String.equal k key | None -> false
  in
  match List.find_opt full (Array.to_list (Web.query_all (Web.document ()) "script[data-yuka-answer]")) with
  | None -> None
  | Some el -> (
      match Json.of_string (Web.text_content el) with
      | Ok (`Assoc [ ("ok", j) ]) -> Some (Ok j)
      | Ok (`Assoc [ ("error", e) ]) -> ( match error e with Some e -> Some (Error e) | None -> None)
      | _ -> None)
