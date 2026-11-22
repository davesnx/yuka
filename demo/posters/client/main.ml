open Posters_shared

let save : string -> string -> unit =
  [%mel.raw
    {|function (name, svg) { var url = URL.createObjectURL(new Blob([svg], { type: "image/svg+xml" })); var link = document.createElement("a"); link.href = url; link.download = name; document.body.appendChild(link); link.click(); link.remove(); setTimeout(function () { URL.revokeObjectURL(url) }, 1000) }|}]

let png : string -> string -> unit =
  [%mel.raw
    {|function (name, svg) { var url = URL.createObjectURL(new Blob([svg], { type: "image/svg+xml" })); var image = new Image(); image.onload = function () { var canvas = document.createElement("canvas"); canvas.width = image.naturalWidth * 2; canvas.height = image.naturalHeight * 2; canvas.getContext("2d").drawImage(image, 0, 0, canvas.width, canvas.height); URL.revokeObjectURL(url); canvas.toBlob(function (blob) { var href = URL.createObjectURL(blob); var link = document.createElement("a"); link.href = href; link.download = name; document.body.appendChild(link); link.click(); link.remove(); setTimeout(function () { URL.revokeObjectURL(href) }, 1000) }, "image/png") }; image.src = url }|}]

let () =
  Download.svg := save;
  Download.png := png;
  Yuka.render ~islands ()
