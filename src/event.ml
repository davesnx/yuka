open Platform

type t = Types.event

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
let client_x e = !platform.client_x e
let client_y e = !platform.client_y e
