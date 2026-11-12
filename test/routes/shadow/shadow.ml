module List = struct end
module String = struct end

type no = No

let ( ^ ) No No = No
let ( @ ) No No = No
let ( = ) No No = No
let string_of_int No = No
let string_of_bool No = No

type result = Ok | Error

type fields = {
  rules : no;
  guards : no;
  fallback : no;
  load : no;
  layers : no;
  page : no;
  key : no;
  data : no;
  wrap : no;
  not_found : no;
  error : no;
  action : no;
  cross_origin : no;
  run : no;
}

let app = No
let resolve = No
let rules = No
let req = No
let route = No
let path = No
let children = No
let missing = No
let find = No
let href = No
