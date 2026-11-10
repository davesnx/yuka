type view = All | Mine [@@deriving codec]
type label_count = { label : string; open_ : int } [@@deriving codec]

let labels = Yuka.Action.query ~name:"labels" ~input:Yuka.Codec.unit ~output:(Yuka.Codec.list label_count_codec)
