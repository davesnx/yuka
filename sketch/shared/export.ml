let color_hex : Shape.color -> string = function
  | Black -> "#1d1d1f"
  | Grey -> "#8a8f98"
  | Red -> "#e03131"
  | Orange -> "#f08c00"
  | Yellow -> "#e8b500"
  | Green -> "#2f9e44"
  | Blue -> "#1c7ed6"
  | Violet -> "#7048e8"

let tint_hex : Shape.color -> string = function
  | Black -> "#e9e9ec"
  | Grey -> "#eef0f2"
  | Red -> "#ffe3e3"
  | Orange -> "#fff0d6"
  | Yellow -> "#fff6c7"
  | Green -> "#dcf5e0"
  | Blue -> "#dbeeff"
  | Violet -> "#ebe5ff"

let font_family = "ui-rounded, 'SF Pro Rounded', 'Nunito', system-ui, -apple-system, 'Segoe UI', sans-serif"

let escape s =
  let b = Buffer.create (String.length s) in
  String.iter
    (function
      | '&' -> Buffer.add_string b "&amp;"
      | '<' -> Buffer.add_string b "&lt;"
      | '>' -> Buffer.add_string b "&gt;"
      | '"' -> Buffer.add_string b "&quot;"
      | c -> Buffer.add_char b c)
    s;
  Buffer.contents b

let paint = function Render.Ink c -> color_hex c | Tint c -> tint_hex c | No_paint -> "none"

let part b = function
  | Render.Path { d; fill; stroke; width } ->
      Buffer.add_string b "<path d=\"";
      Buffer.add_string b d;
      Buffer.add_string b "\" fill=\"";
      Buffer.add_string b (paint fill);
      Buffer.add_string b "\"";
      (match stroke with
      | No_paint -> ()
      | _ ->
          Buffer.add_string b " stroke=\"";
          Buffer.add_string b (paint stroke);
          Buffer.add_string b "\" stroke-width=\"";
          Buffer.add_string b (Num.to_string width);
          Buffer.add_string b "\" stroke-linecap=\"round\" stroke-linejoin=\"round\"");
      Buffer.add_string b "/>"
  | Text { lines; x; size; color } ->
      Buffer.add_string b "<text font-size=\"";
      Buffer.add_string b (Num.to_string size);
      Buffer.add_string b "\" fill=\"";
      Buffer.add_string b (color_hex color);
      Buffer.add_string b "\" xml:space=\"preserve\">";
      List.iter
        (fun (line, y) ->
          Buffer.add_string b "<tspan x=\"";
          Buffer.add_string b (Num.to_string x);
          Buffer.add_string b "\" y=\"";
          Buffer.add_string b (Num.to_string y);
          Buffer.add_string b "\">";
          Buffer.add_string b (escape line);
          Buffer.add_string b "</tspan>")
        lines;
      Buffer.add_string b "</text>"

let svg metrics board =
  match Board.all_bounds board with
  | None -> None
  | Some bounds ->
      let box = Geom.Box.expand bounds 32. in
      let b = Buffer.create 4096 in
      let n = Num.to_string in
      Buffer.add_string b "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"";
      Buffer.add_string b (String.concat " " [ n box.x; n box.y; n box.w; n box.h ]);
      Buffer.add_string b "\" width=\"";
      Buffer.add_string b (n box.w);
      Buffer.add_string b "\" height=\"";
      Buffer.add_string b (n box.h);
      Buffer.add_string b "\" font-family=\"";
      Buffer.add_string b (escape font_family);
      Buffer.add_string b "\"><rect x=\"";
      Buffer.add_string b (n box.x);
      Buffer.add_string b "\" y=\"";
      Buffer.add_string b (n box.y);
      Buffer.add_string b "\" width=\"";
      Buffer.add_string b (n box.w);
      Buffer.add_string b "\" height=\"";
      Buffer.add_string b (n box.h);
      Buffer.add_string b "\" fill=\"#fbfaf7\"/>";
      Array.iter
        (fun (s : Shape.t) ->
          Buffer.add_string b "<g transform=\"";
          Buffer.add_string b (Render.transform s);
          Buffer.add_string b "\">";
          List.iter (part b) (Render.parts metrics s);
          Buffer.add_string b "</g>")
        (Board.shapes board);
      Buffer.add_string b "</svg>";
      Some (Buffer.contents b)
