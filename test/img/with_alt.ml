let image = { Yuka.Image.src = "/_yuka/img/a-1.png"; width = 2; height = 1; srcset = [] }
let page : Yuka.server Yuka.element = Yuka.Img.make ~src:image ~alt:"A" ()
