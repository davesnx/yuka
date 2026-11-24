open Posters_shared

let png : string -> string -> unit =
  [%mel.raw
    {|function (name, url) { var image = new Image(); image.onload = function () { var canvas = document.createElement("canvas"); canvas.width = image.naturalWidth * 2; canvas.height = image.naturalHeight * 2; canvas.getContext("2d").drawImage(image, 0, 0, canvas.width, canvas.height); canvas.toBlob(function (blob) { var href = URL.createObjectURL(blob); var link = document.createElement("a"); link.href = href; link.download = name; document.body.appendChild(link); link.click(); link.remove(); setTimeout(function () { URL.revokeObjectURL(href) }, 1000) }, "image/png") }; image.src = url }|}]

let angle : Yuka.Event.t -> int option =
  [%mel.raw
    {|function (event) { var dial = event.target.closest && event.target.closest(".dial"); if (!dial || (event.type === "pointermove" && !(event.buttons & 1))) return undefined; if (event.type === "pointerdown") { dial.setPointerCapture(event.pointerId); dial.focus() } var box = dial.getBoundingClientRect(); var degrees = Math.atan2(event.clientX - box.left - box.width / 2, box.top + box.height / 2 - event.clientY) * 180 / Math.PI; return (Math.round(degrees) + 360) % 360 }|}]

let () =
  Download.png := png;
  Dial.angle := angle;
  Yuka.render ~islands ()
