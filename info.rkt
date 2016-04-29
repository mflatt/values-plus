#lang info

(define collection "values+")

(define description "Generalization of multiple-value results to keyword results")

(define pkgs-authors '(jay))

(define deps '("base"))

(define scribblings '[("values+.scrbl")])

(define version "1.0")
(define build-deps '("eli-tester"
                     "racket-doc"
                     "rackunit-lib"
                     "scribble-lib"))
