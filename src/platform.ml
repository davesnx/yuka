open Types
open Base

let browser_only _ = failwith "Yuka: this function runs only in the browser"

let platform =
  ref
    {
      target_value = browser_only;
      target_checked = browser_only;
      key = browser_only;
      meta_key = browser_only;
      ctrl_key = browser_only;
      prevent_default = browser_only;
      on_window = (fun _ _ -> browser_only ());
      stop_propagation = browser_only;
      target_tag = browser_only;
      shift_key = browser_only;
      alt_key = browser_only;
      navigate = browser_only;
      focus = browser_only;
      scroll_into_view = browser_only;
    }

module Event = struct
  type t = event

  let target_value e = !platform.target_value e
  let target_checked e = !platform.target_checked e
  let key e = !platform.key e
  let meta_key e = !platform.meta_key e
  let ctrl_key e = !platform.ctrl_key e
  let prevent_default e = !platform.prevent_default e
  let stop_propagation e = !platform.stop_propagation e
  let target_tag e = !platform.target_tag e
  let shift_key e = !platform.shift_key e
  let alt_key e = !platform.alt_key e
end

module Browser = struct
  let on_window name handler = own (!platform.on_window name handler)
  let navigate url = !platform.navigate url
  let focus id = !platform.focus id
  let scroll_into_view id = !platform.scroll_into_view id
end
