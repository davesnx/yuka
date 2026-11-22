yuka i18n reads DIR/LOCALE.messages, one file per locale, and prints a module
with a function per message. The base locale gives the keys that every other
locale must have:

  $ mkdir messages
  $ cat > messages/en.messages <<'EOF'
  > # Comments and blank lines are skipped
  > 
  > greeting = Hello, {name}!
  > title = Issues
  > count = {{n}} is {n} of {total}
  > EOF
  $ cat > messages/pt-BR.messages <<'EOF'
  > title = Tarefas
  > greeting = Olá, {name}!
  > count = {{n}} é {n} de {total}
  > EOF
  $ yuka i18n --dir messages --base en > messages.ml
  $ grep -v '^$' messages.ml
  type locale = En | Pt_BR
  let locales = [ En; Pt_BR ]
  let base = En
  let tag = function En -> "en" | Pt_BR -> "pt-BR"
  let of_tag = function "en" -> Some En | "pt-BR" -> Some Pt_BR | _ -> None
  let locale_param = Yuka.Router.Param.make ~decode:of_tag ~encode:tag
  let locale_codec =
    Yuka.Codec.make
      ~encode:(fun locale -> `String (tag locale))
      ~decode:(function
        | `String text -> ( match of_tag text with Some locale -> Ok locale | None -> Error ("unknown locale " ^ text))
        | _ -> Error "a locale is a string")
  let context : locale Yuka.Context.t = Yuka.Context.make ~name:"yuka.locale" ~codec:locale_codec ()
  let current () = match Yuka.Context.get context with Some locale -> locale | None -> base
  module En = struct
    let greeting ~name = {js|Hello, |js} ^ name ^ {js|!|js}
    let title = {js|Issues|js}
    let count ~n ~total = {js|{n} is |js} ^ n ^ {js| of |js} ^ total
  end
  module Pt_BR = struct
    let title = {js|Tarefas|js}
    let greeting ~name = {js|Olá, |js} ^ name ^ {js|!|js}
    let count ~n ~total = {js|{n} é |js} ^ n ^ {js| de |js} ^ total
  end
  let greeting locale ~name =
    match locale with
    | En -> {js|Hello, |js} ^ name ^ {js|!|js}
    | Pt_BR -> {js|Olá, |js} ^ name ^ {js|!|js}
  let title locale =
    match locale with
    | En -> {js|Issues|js}
    | Pt_BR -> {js|Tarefas|js}
  let count locale ~n ~total =
    match locale with
    | En -> {js|{n} is |js} ^ n ^ {js| of |js} ^ total
    | Pt_BR -> {js|{n} é |js} ^ n ^ {js| de |js} ^ total

The module builds with Yuka. A message with all its arguments builds; a
message with a missing argument does not:

  $ unset DUNE_BUILD_DIR
  $ unset CLICOLOR_FORCE
  $ export OCAMLPATH="$(dirname "$(command -v yuka)")/../lib"
  $ printf '(lang dune 3.16)\n' > dune-project
  $ printf '(executable (name main) (libraries yuka))\n' > dune
  $ cat > main.ml <<'EOF'
  > let () = print_endline (Messages.greeting Messages.Pt_BR ~name:"Ana" ^ " " ^ Messages.En.count ~n:"1" ~total:"2")
  > EOF
  $ dune build --root . ./main.exe 2>&1
  $ ./_build/default/main.exe
  Olá, Ana! {n} is 1 of 2
  $ cat > main.ml <<'EOF'
  > let () = print_endline (Messages.greeting Messages.Pt_BR)
  > EOF
  $ dune build --root . ./main.exe 2>&1 | grep -o 'This expression has type name:string -> string'
  This expression has type name:string -> string
  $ cat > main.ml <<'EOF'
  > let () = print_endline (Messages.En.count ~n:"1")
  > EOF
  $ dune build --root . ./main.exe 2>&1 | grep -o 'This expression has type total:string -> string'
  This expression has type total:string -> string
  $ rm main.ml dune dune-project

Errors name the file and the line:

  $ yuka i18n --dir messages > /dev/null 2>&1; echo $?
  2
  $ yuka i18n --dir messages --base fr
  yuka i18n: messages: no file fr.messages for the base locale
  [1]
  $ printf 'title = Tarefas\ngreeting = Olá, {nome}!\ncount = {n} {total}\n' > messages/pt-BR.messages
  $ yuka i18n --dir messages --base en
  yuka i18n: messages/pt-BR.messages:2: greeting takes {nome}, but messages/en.messages:3 takes {name}
  [1]
  $ printf 'title = Tarefas\ncount = {n} {total}\n' > messages/pt-BR.messages
  $ yuka i18n --dir messages --base en
  yuka i18n: messages/pt-BR.messages: no message greeting (messages/en.messages:3)
  [1]
  $ printf 'title = Tarefas\ngreeting = {name}\ncount = {n} {total}\nextra = x\n' > messages/pt-BR.messages
  $ yuka i18n --dir messages --base en
  yuka i18n: messages/pt-BR.messages:4: the key extra is not in messages/en.messages
  [1]
  $ rm messages/pt-BR.messages
  $ for line in 'a = x' 'a = x\na = y' 'Title = x' 'type = x' 'tag = x' 'a = {Name}' 'a = {locale}' 'a = {x' 'a = x}' 'a = |js}}'; do
  >   printf "$line\n" > messages/en.messages; yuka i18n --dir messages --base en > /dev/null; done; true
  yuka i18n: messages/en.messages:2: the key a is already at line 1
  yuka i18n: messages/en.messages:1: "Title" is not a valid key; use a lowercase OCaml name that is not a keyword
  yuka i18n: messages/en.messages:1: "type" is not a valid key; use a lowercase OCaml name that is not a keyword
  yuka i18n: messages/en.messages:1: the key tag is a name of the generated module; choose another key
  yuka i18n: messages/en.messages:1: {Name} is not a valid argument name; use a lowercase OCaml name
  yuka i18n: messages/en.messages:1: {locale} is the first argument of each message; choose another name
  yuka i18n: messages/en.messages:1: a { with no }; write {{ for the character
  yuka i18n: messages/en.messages:1: a } with no {; write }} for the character
  yuka i18n: messages/en.messages:1: the text cannot contain |js}
  $ printf 'a = x\n' > messages/en.messages && printf 'a = x\n' > messages/1x.messages
  $ yuka i18n --dir messages --base en
  yuka i18n: messages/1x.messages: "1x" is not a locale name; use letters, digits and -, starting with a letter
  [1]

Lines that start with @ give the number and date formats of the locale.
A file with one format line has all four, and each locale has them when
the base locale has them. The module gets a Yuka.Locale.t for each locale:

  $ rm messages/1x.messages
  $ printf 'a = x\n@decimal = .\n@group = ,\n@months = Jan, Feb, Mar, Apr, May, Jun, Jul, Aug, Sep, Oct, Nov, Dec\n@date = {month} {day}, {year}\n' > messages/en.messages
  $ printf 'a = x\n@decimal = ,\n@group = .\n@months = ene, feb, mar, abr, may, jun, jul, ago, sep, oct, nov, dic\n@date = {dd}/{mm}/{year}\n' > messages/es.messages
  $ yuka i18n --dir messages --base en > messages.ml
  $ grep -A3 'let format :' messages.ml; grep '^let format' messages.ml
    let format : Yuka.Locale.t =
      { decimal = {js|.|js}; group = {js|,|js};
        months = [| {js|Jan|js}; {js|Feb|js}; {js|Mar|js}; {js|Apr|js}; {js|May|js}; {js|Jun|js}; {js|Jul|js}; {js|Aug|js}; {js|Sep|js}; {js|Oct|js}; {js|Nov|js}; {js|Dec|js} |];
        date = {js|{month} {day}, {year}|js} }
  --
    let format : Yuka.Locale.t =
      { decimal = {js|,|js}; group = {js|.|js};
        months = [| {js|ene|js}; {js|feb|js}; {js|mar|js}; {js|abr|js}; {js|may|js}; {js|jun|js}; {js|jul|js}; {js|ago|js}; {js|sep|js}; {js|oct|js}; {js|nov|js}; {js|dic|js} |];
        date = {js|{dd}/{mm}/{year}|js} }
  let format = function En -> En.format | Es -> Es.format
  $ printf '(lang dune 3.16)\n' > dune-project
  $ printf '(executable (name main) (libraries yuka))\n' > dune
  $ cat > main.ml <<'EOF'
  > let f = Messages.format Messages.Es
  > let () = print_endline (Yuka.Locale.float f ~digits:2 (-1234567.891) ^ " " ^ Yuka.Locale.date f ~year:2026 ~month:3 ~day:7)
  > EOF
  $ dune build --root . ./main.exe 2>&1
  $ ./_build/default/main.exe
  -1.234.567,89 07/03/2026
  $ rm main.ml dune dune-project

Errors in format lines:

  $ printf 'a = x\n' > messages/es.messages
  $ yuka i18n --dir messages --base en
  yuka i18n: messages/es.messages: no format lines, but messages/en.messages has them
  [1]
  $ printf 'a = x\n' > messages/en.messages
  $ printf 'a = x\n@decimal = ,\n@group = .\n@months = 1,2,3,4,5,6,7,8,9,10,11,12\n@date = {day}\n' > messages/es.messages
  $ yuka i18n --dir messages --base en
  yuka i18n: messages/es.messages: format lines, but messages/en.messages has none
  [1]
  $ rm messages/es.messages
  $ for line in '@decimal = .' '@decimal = .\n@decimal = ,' '@size = 1' '@months = a, b' '@months = a,,c,d,e,f,g,h,i,j,k,l' '@date = {week}' '@date = {day' '@group = |js}'; do
  >   printf "a = x\n$line\n" > messages/en.messages; yuka i18n --dir messages --base en > /dev/null; done; true
  yuka i18n: messages/en.messages:2: no @group; a file with a format line needs @decimal, @group, @months, @date
  yuka i18n: messages/en.messages:3: @decimal is already at line 2
  yuka i18n: messages/en.messages:2: @size is not a format line; use @decimal, @group, @months, @date
  yuka i18n: messages/en.messages:2: @months takes the 12 month names, separated by commas
  yuka i18n: messages/en.messages:2: @months takes the 12 month names, separated by commas
  yuka i18n: messages/en.messages:2: {week} is not a date field; use {year}, {month}, {mm}, {day}, {dd}
  yuka i18n: messages/en.messages:2: a { with no }; write {{ for the character
  yuka i18n: messages/en.messages:2: the text cannot contain |js}
