open Genart_shared

(* Draws the <svg id="sketch"> on a canvas of 2048 px, the size of the original sketch,
   and saves it. *)
let png : string -> unit =
  [%mel.raw
    {|function (name) { var svg = document.getElementById("sketch"); if (!svg) return; var source = new XMLSerializer().serializeToString(svg); var url = URL.createObjectURL(new Blob([source], { type: "image/svg+xml" })); var image = new Image(); image.onload = function () { var canvas = document.createElement("canvas"); canvas.width = 2048; canvas.height = 2048; canvas.getContext("2d").drawImage(image, 0, 0, 2048, 2048); URL.revokeObjectURL(url); canvas.toBlob(function (blob) { var href = URL.createObjectURL(blob); var link = document.createElement("a"); link.href = href; link.download = name; document.body.appendChild(link); link.click(); link.remove(); setTimeout(function () { URL.revokeObjectURL(href) }, 1000) }, "image/png") }; image.src = url }|}]

let () =
  Export.png := png;
  Yuka.render ~islands ()
