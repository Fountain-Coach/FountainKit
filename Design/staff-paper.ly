% A4 blank staff paper matching the design (12 systems, margins, spacing)
% LilyPond 2.24+
\version "2.24.0"

% Page + spacing to mirror the SVG template
\paper {
  #(set-paper-size "a4")
  left-margin = 15\mm
  right-margin = 15\mm
  top-margin = 15\mm
  bottom-margin = 15\mm
  indent = 0\mm
  ragged-right = ##f
  ragged-last-bottom = ##f

  % Vertical distances (in mm)
  top-system-spacing = #'((basic-distance . 25) (minimum-distance . 25) (padding . 0.5))
  system-system-spacing = #'((basic-distance . 12) (minimum-distance . 10) (padding . 0.5))
}

% Approximate staff metrics: 1.8 mm between staff lines
% staff-space(mm) = (set-global-staff-size pt / 4) * 0.3528
% Solve for ~1.8 mm => ~20.4 pt
\layout {
  #(set-global-staff-size 20.4)
  \context {
    \Score
    \remove "Bar_number_engraver"
  }
  \context {
    \Staff
    \remove "Clef_engraver"
    \remove "Time_signature_engraver"
    % Hide bar lines and key signatures to resemble blank staff paper
    \override BarLine.stencil = ##f
    \override KeySignature.stencil = ##f
  }
}

% Content: 12 systems, 4 measures per system, sketched as invisible skips
music = {
  \repeat unfold 12 { s1*4 \break }
}

\header {
  title = "Title"
  composer = "Composer • Subtitle"
  tagline = ""
}

\score { \new Staff \music }

