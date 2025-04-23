#lang scribble/manual
@(require (for-label racket/base
                     racket/contract/base
                     values+))

@title{Multiple and Keyword Return Values}
@author{@(author+email "Jay McCarthy" "jay@racket-lang.org")}

@defmodule[values+]

@defproc[(values+ [v any/c] ... [#:<kw> kw-arg any/c] ...) any]{

Like @racket[values], but with support for keyword arguments as
received by @racket[call-with-values+], @racket[define-values+],
@racket[let-values+], or @racket[let*-values+].

If no keyword arguments are provided to @racket[values+], then it
returns results equivalent to using @racket[values].

If keyword arguments provided to @racket[values+], then the values are
returned via @racket[values], and using a particular encoding that is
not meant to be inspected directly (except by the implementation of
@racket[call-with-values+], etc.). Currently, the encoding is multiple
values as follows: a generated symbol that effectively tags the
results as keyword results, a list of keywords, a list of values in
parallel to the keyword list, and the remaining non-keyword values.}


@defproc[(call-with-values+ [generator (-> any)] [receiver procedure?]) any]{

Like @racket[call-with-values], but keyword arguments returned via
@racket[values+] can be received as keyword arguments of
@racket[receiver]. If @racket[receiver] has no required keyword
arguments, then it can also receive a single return value from
@racket[generator] or multiple non-keyword values.}


@deftogether[(
@defform[(define-values+ kw-formals rhs-expr)]
@defform[(let-values+ ([kw-formals rhs-expr] ...) body ...+)]
@defform[(let*-values+ ([kw-formals rhs-expr] ...) body ...+)]
)]{

Like @racket[define-values], @racket[let-values], and @racket[let*-values],
but supporting @racket[kw-formals] as in @racket[lambda] to receive
optional and keyword return values from @racket[rhs-expr].}
