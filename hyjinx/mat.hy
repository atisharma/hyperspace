"
Convenience things for ndarrays, matrices and numerical data.
"

(require hyrule [unless ncut
                 -> ->> as->])

(import hyrule [inc dec])
(import functools [reduce partial]
        cytoolz [last])

(import numpy)
(import random [randint])
(import shutil)
(import operator)
(import pansi [ansi :as _ansi])


;; * Matrices
;; ----------------------------------------------------

(setv _colors [_ansi.blue
               _ansi.green
               _ansi.yellow
               _ansi.cyan
               _ansi.magenta
               _ansi.BLUE
               _ansi.GREEN
               _ansi.MAGENTA
               _ansi.CYAN
               _ansi.MAGENTA])

(defn ppa [a #** kwargs]
  "Pretty-print a numpy ndarray."
  (let [col (get _colors (% (len _colors) a.ndim))]
    (match a.ndim
           1 (print (_add-corners-1d a #** kwargs))
           2 (print (_add-corners-2d a #** kwargs))
           _ (do
               (list (map (partial ppa #** kwargs) a))
               (print (+ col
                         (describe a)
                         _ansi.reset))))))

(defn describe [a]
  f"{a.ndim}D: {(.join "×" (map str a.shape))}  ({(prod a.shape)} elements)  {a.dtype}  {a.nbytes}B")

(defn _pformat-array [a * [precision 3] [digits None] [thou-sep ","] [suppress-small True] [formatter None]]
  "Wrap sub-array (matrix) with a border and return a string."
  (let [digits (+ 4
                  (or digits (int (numpy.log10 (numpy.max (abs a))))))
        formatter (or formatter {"float_kind" (fn [x] f" {x :=+{(+ precision digits)}_.{precision}f} ")
                                 "int_kind" (fn [x] f" {x :=+{digits}_d} ")
                                 "complex_kind" (fn [x] f" {x :=+{(+ precision digits)}_.{precision}f} ")})
        ts (shutil.get-terminal-size)
        width (- ts.columns 8)
        s (numpy.array2string a :formatter formatter
                                :suppress-small suppress-small
                                :separator "  "
                                :max-line-width width)]
    (-> s
        (.replace "_" thou-sep)
        (.replace "[ " " ")
        (.replace " ]" " "))))

(defn _add-corners-1d [v #** kwargs]
  "Add nice corners to _pformatted ndarray of dimension 1."
  (let [padding "  "
        s (_pformat-array v #** kwargs)
        br-width (+ 2 (len s))
        tl-corner f"{_ansi.green}╭── {(describe v)}\n│{_ansi.reset}"
        br-corner f"{_ansi.green}│\n{"──╯" :>{br-width}}{_ansi.reset} "]
    (+ tl-corner s br-corner)))

(defn _add-corners-2d [m #** kwargs]
  "Add nice corners to _pformatted ndarray of dimension 2."
  (let [padding "  "
        s (_pformat-array m #** kwargs)
        lines (.split s "\n")
        br-width (len (last lines))
        tl-corner f"{_ansi.blue}╭── {(describe m)}\n│{_ansi.reset} "
        br-corner f" {_ansi.blue}│\n{"──╯" :>{br-width}}{_ansi.reset} "]
    (-> s
        (.replace "[ " tl-corner)
        (.replace " ]" br-corner))))


;; * Numeric
;; ----------------------------------------------------

(defn dice [n]
  "True 1/n of the time."
  (not (randint 0 (- n 1))))

(defn prod [l]
  "The product of the elements in l."
  (reduce operator.mul l))
