yuka assets reads the size of each PNG, JPEG, GIF and WebP file from its
header, copies the file with a hash of its content in the name and prints a
module with one Yuka.Image.t per file. Other files are skipped.

  $ mkdir images
  $ printf '\211PNG\r\n\032\n\000\000\000\rIHDR\000\000\002\200\000\000\001\340' > images/Hero.png
  $ printf '\377\330\377\340\000\004xx\377\300\000\011\010\000\144\000\310\003' > images/photo.jpg
  $ printf 'GIF89a\012\000\005\000' > images/dot.gif
  $ printf 'RIFF\000\000\000\000WEBPVP8X\012\000\000\000\000\000\000\000\077\001\000\357\000\000' > images/wide.webp
  $ printf 'RIFF\000\000\000\000WEBPVP8L\000\000\000\000\057\143\100\076\000' > images/lossless.webp
  $ printf 'notes' > images/README.md
  $ yuka assets --dir images --out img
  let hero : Yuka.Image.t =
    { Yuka.Image.src = "/_yuka/img/hero-3aa82b9b.png"; width = 640; height = 480;
      srcset = [ ("/_yuka/img/hero-3aa82b9b.png", 640) ] }
  let dot : Yuka.Image.t =
    { Yuka.Image.src = "/_yuka/img/dot-cc3a4e41.gif"; width = 10; height = 5;
      srcset = [ ("/_yuka/img/dot-cc3a4e41.gif", 10) ] }
  let lossless : Yuka.Image.t =
    { Yuka.Image.src = "/_yuka/img/lossless-018aa104.webp"; width = 100; height = 250;
      srcset = [ ("/_yuka/img/lossless-018aa104.webp", 100) ] }
  let photo : Yuka.Image.t =
    { Yuka.Image.src = "/_yuka/img/photo-0410de14.jpg"; width = 200; height = 100;
      srcset = [ ("/_yuka/img/photo-0410de14.jpg", 200) ] }
  let wide : Yuka.Image.t =
    { Yuka.Image.src = "/_yuka/img/wide-778176ac.webp"; width = 320; height = 240;
      srcset = [ ("/_yuka/img/wide-778176ac.webp", 320) ] }
  $ ls img
  dot-cc3a4e41.gif
  hero-3aa82b9b.png
  lossless-018aa104.webp
  photo-0410de14.jpg
  wide-778176ac.webp
  $ cmp images/Hero.png img/hero-*.png

A second run gives the same files and the same module:

  $ yuka assets --dir images --out img > first.ml
  $ yuka assets --dir images --out img > second.ml
  $ cmp first.ml second.ml

Smaller copies need --widths and the vips command. Without vips on PATH, the
command says so and writes only the files:

  $ PATH=/nonexistent:$(dirname $(command -v yuka)) yuka assets --dir images --out plain --widths 64,128 > plain.ml
  yuka assets: vips is not on PATH: no smaller copies
  $ cmp first.ml plain.ml

With vips, each width under the width of the file gets a copy. This vips
writes a fixed 320x240 PNG to show the call:

  $ mkdir bin
  $ cat > bin/vips <<'X'
  > #!/bin/sh
  > echo "vips $*" | sed "s|$PWD/||g" >&2
  > printf '\211PNG\r\n\032\n\000\000\000\rIHDR\000\000\001\100\000\000\000\360' > "$3"
  > X
  $ chmod +x bin/vips
  $ PATH=$PWD/bin:$PATH yuka assets --dir images --out sized --widths 320,9999 | grep -A2 'let hero'
  vips thumbnail images/Hero.png sized/.hero-320.png 320
  let hero : Yuka.Image.t =
    { Yuka.Image.src = "/_yuka/img/hero-3aa82b9b.png"; width = 640; height = 480;
      srcset = [ ("/_yuka/img/hero-320w-cc711ffe.png", 320); ("/_yuka/img/hero-3aa82b9b.png", 640) ] }
  $ ls sized | grep hero
  hero-320w-cc711ffe.png
  hero-3aa82b9b.png

Errors:

  $ printf 'not an image' > images/broken.png
  $ yuka assets --dir images --out img
  yuka assets: images/broken.png: not a PNG, JPEG, GIF or WebP file
  [1]
  $ rm images/broken.png
  $ cp images/dot.gif images/DOT.gif
  $ yuka assets --dir images --out img
  yuka assets: two files of images give the name dot
  [1]
  $ rm images/DOT.gif
  $ yuka assets --out img 2>&1 | head -1
  yuka assets: give --dir.
  $ yuka assets --out img > /dev/null 2>&1; echo $?
  2
  $ yuka assets --dir images --out img --widths 64,x
  yuka assets: --widths: "x" is not a width in pixels
  [1]
