type status = Open | Closed [@@deriving codec]

type priority = Low | Level of int | Custom of string * bool | Range of { lo : int; hi : int }
[@@deriving codec]

type point = int * float [@@deriving codec]

type issue = {
  id : int;
  title : string;
  note : string option;
  tags : string list;
  status : status;
  priority : priority;
  at : point;
  scores : float array;
}
[@@deriving codec]

type id = int [@@deriving codec]

type loaded = { items : int list Yuka.Async.t; other : string Yuka.Async.t } [@@deriving codec]

type 'a tree = Leaf | Node of 'a tree * 'a * 'a tree [@@deriving codec]
type rose = { label : string; kids : rose list } [@@deriving codec]

type expr = Num of int | Block of stmts
and stmts = stmt list
and stmt = Do of expr | Let of { name : string; value : expr }
[@@deriving codec]

type pair = int tree * string tree [@@deriving codec]
type ('a, 'b) either = Left of 'a | Right of 'b [@@deriving codec]
type nested = int list tree option [@@deriving codec]

type outcome = (int tree, string) result [@@deriving codec]
type outcome2 = (int, status) Result.t [@@deriving codec]
type outcome3 = (int, string) Stdlib.result list [@@deriving codec]
