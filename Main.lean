import VersoSlides
import Slides

open VersoSlides

def customCss : CssFile where
  filename := "custom.css"
  contents := ⟨include_str "static/custom.css"⟩

def main : IO UInt32 :=
  slidesMain
    (config := {
      theme       := "white",
      center      := false,
      margin      := 0,
      slideNumber := true,
      transition  := "fade",
      extraCss    := #[customCss]
    })
    (doc := %doc Slides)
