open Posters_shared

let png : string -> string -> unit =
  [%mel.raw
    {|function (name, url) { var image = new Image(); image.onload = function () { var canvas = document.createElement("canvas"); canvas.width = image.naturalWidth * 2; canvas.height = image.naturalHeight * 2; canvas.getContext("2d").drawImage(image, 0, 0, canvas.width, canvas.height); canvas.toBlob(function (blob) { var href = URL.createObjectURL(blob); var link = document.createElement("a"); link.href = href; link.download = name; document.body.appendChild(link); link.click(); link.remove(); setTimeout(function () { URL.revokeObjectURL(href) }, 1000) }, "image/png") }; image.src = url }|}]

let () =
  Download.png := png;
  Yuka.render ~islands ()
