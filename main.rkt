#lang racket/base
(require (for-syntax racket/base
                     syntax/parse
                     syntax/stx)
         racket/contract/base
         racket/contract/combinator)

(provide values+
         call-with-values+
         let-values+
         let*-values+
         define-values+)

;; Uses the convention that a values+ has four parts: a code and the
;; arguments to keyword-apply

(define value+-code
  (gensym))

(define (call-with-values+ producer consumer)
  (call-with-values producer
    (case-lambda
      [(maybe-key kws kw-args . rest)
       (if (eq? value+-code maybe-key)
           (keyword-apply consumer kws kw-args rest)
           (apply consumer maybe-key kws kw-args rest))]
      [args
       (apply consumer args)])))

(define values+
  (make-keyword-procedure
   (lambda (kws kw-args . rest)
     (apply values value+-code kws kw-args rest))
   (procedure-rename values 'values+)))

;; These macros are obvious
(define-syntax-rule (let-values+/one ([formals expr]) body0 body1 ...)
  (call-with-values+ (lambda () expr) (lambda formals body0 body1 ...)))

(define-syntax (let*-values+ stx)
  (syntax-case stx ()
    [(_ () body0 body1 ...)
     (syntax/loc stx
       (let () body0 body1 ...))]
    [(_ ([formals expr]) body0 body1 ...)
     (syntax/loc stx
       (let-values+/one ([formals expr]) body0 body1 ...))]
    [(_ ([formals0 expr0] [formals1 expr1] ...) body0 body1 ...)
     (syntax/loc stx
       (let-values+/one ([formals0 expr0])
                        (let*-values+ ([formals1 expr1] ...) body0 body1 ...)))]))

;; let-values+ is harder because we need to make sure the same things
;; are visible This function creates new names with the same structure
;; so let*-values+ can be used.
(define-for-syntax (generate-temporaries-for-formals stx)
  (syntax-parse stx
    [()
     (values #'()
             null
             null)]
    [rest:id
     (with-syntax ([(tmp-rest) (generate-temporaries #'(rest))])
       (values #'tmp-rest
               (list #'rest)
               (list #'tmp-rest)))]
    [(arg:id . more)
     (let-values ([(more-tmp-stx more-ids more-tmp-ids)
                   (generate-temporaries-for-formals #'more)])
       (with-syntax ([more-tmp more-tmp-stx]
                     [(tmp-arg) (generate-temporaries #'(arg))])
         (values #'(tmp-arg . more-tmp)
                 (list* #'arg more-ids)
                 (list* #'tmp-arg more-tmp-ids))))]
    [(kw:keyword . more)
     (let-values ([(more-tmp-stx more-ids more-tmp-ids)
                   (generate-temporaries-for-formals #'more)])
       (with-syntax ([more-tmp more-tmp-stx])
         (values #'(kw . more-tmp)
                 more-ids more-tmp-ids)))]
    [([arg:id default:expr] . more)
     (let-values ([(more-tmp-stx more-ids more-tmp-ids)
                   (generate-temporaries-for-formals #'(arg . more))])
       (with-syntax ([(tmp-arg . more-tmp) more-tmp-stx])
         (values #'([tmp-arg default] . more-tmp)
                 more-ids more-tmp-ids)))]))

(begin-for-syntax
  (define (generate-temporaries-for-formals/list stx)
    (define-values (tmp-stx stx-ids stx-tmp-ids)
      (generate-temporaries-for-formals stx))
    (list tmp-stx stx-ids stx-tmp-ids)))

(define-syntax (let-values+ stx)
  (syntax-case stx ()
    [(_ () body0 body1 ...)
     (syntax/loc stx
       (let () body0 body1 ...))]
    [(_ ([formals expr]) body0 body1 ...)
     (syntax/loc stx
       (let-values+/one ([formals expr]) body0 body1 ...))]
    [(_ ([formals expr] ...) body0 body1 ...)
     (with-syntax ([((temp-formals (formal-id ...) (temp-formal-id ...))
                     ...)
                    (stx-map generate-temporaries-for-formals/list
                             #'(formals ...))])
       (syntax/loc stx
         (let*-values+ ([temp-formals expr] ...)
                       (let-values ([(formal-id ...) (values temp-formal-id ...)]
                                    ...)
                         body0 body1 ...))))]))

(define-syntax (define-values+ stx)
  (syntax-case stx ()
    [(_ formals rhs)
     (let ()
       (define-values (tmp-stx stx-ids stx-tmp-ids)
         (generate-temporaries-for-formals #'formals))
       (quasisyntax/loc stx
         (define-values #,stx-ids
           (let-values+/one ([formals rhs]) (values . #,stx-ids)))))]))

;; Tests
(module+ test
  (require tests/eli-tester)

  (test
   (call-with-values+ (lambda () (values 1))
                      (lambda (x) x))
   =>
   1

   (call-with-values+ (lambda () (values 2))
                      (lambda (x [y 3]) (list x y)))
   =>
   (list 2 3)

   (call-with-values+ (lambda () 3)
                      (lambda (x) x))
   =>
   3

   (call-with-values+ (lambda () 4)
                      (lambda (x [y 3]) (list x y)))
   =>
   (list 4 3)

   (call-with-values+ (lambda () (values+ 5 #:foo 3))
                      (lambda (x #:foo y) (list x y)))
   =>
   (list 5 3)

   (call-with-values+ (lambda () 6)
                      (lambda (x #:foo [y 3]) (list x y)))
   =>
   (list 6 3)

   (call-with-values+ (lambda () 6)
                      (lambda (x #:foo [y 3]) (set! x 7) (list x y)))
   =>
   (list 7 3)

   (call-with-values+ (lambda () 7)
                      (lambda x x))
   =>
   (list 7)

   (let-values+ ()
                (list 7 2))
   =>
   (list 7 2)

   (let-values+ ([(x) 8]
                 [(y) 2])
                (list x y))
   =>
   (list 8 2)

   (let ([x 2])
     (let-values+ ([(x) 9]
                   [(y) x])
                  (list x y)))
   =>
   (list 9 2)

   (let-values+ ([x 10]
                 [(y) 2])
                (list x y))
   =>
   (list (list 10) 2)

   (let-values+ ([x 10]
                 [(y) 2])
                (set! x (list 11))
                (list x y))
   =>
   (list (list 11) 2)

   (let-values+ ([(x . xs) (values 10 10.2 10.3)]
                 [(y) 2])
                (list x xs y))
   =>
   (list 10 (list 10.2 10.3) 2)

   (let-values+ ([(x [z 3]) 11]
                 [(y) 2])
                (list x y z))
   =>
   (list 11 2 3)

   (let-values+ ([(x #:foo z) (values+ 12 #:foo 3)]
                 [(y) 2])
                (list x y z))
   =>
   (list 12 2 3)

   (let-values+ ([(x #:foo [z 3]) 13]
                 [(y) 2])
                (list x y z))
   =>
   (list 13 2 3)

   (let ()
     (define-values+ (x #:foo z)
       (values+ #:foo 1 2))
     (list x z))
   (list 2 1)))

;; performance
(module+ performance-test
  (define-syntax-rule
    (stress f [label code fun-body] ...)
    (stress*
     (list (cons 'label
                 (λ ()
                   (let ([f (λ () fun-body)])
                     code)))
           ...)))

  (define N (expt 10 5))
  (define (stress* fs)
    (define ts
      (for/list ([l*f (in-list fs)])
        (define l (car l*f))
        (define f (cdr l*f))
        (when #f
          (for ([i (in-range 3)])
            (collect-garbage)))
        (define-values (a ct rt gt)
          (time-apply
           (λ ()
             (for ([i (in-range N)])
               (f)))
           null))
        (cons l ct)))
    (define sts
      (sort ts < #:key cdr))
    (define (/* x y)
      (if (zero? y)
        y
        (/ x y)))
    (for ([l*t (in-list sts)])
      (define l (car l*t))
      (define t (cdr l*t))
      (printf "~a - ~a - ~a\n"
              (real->decimal-string
               (/* t (cdar sts)))
              l
              (real->decimal-string
               t))))

  (stress
   f
   [normal
    (let ([x (f)])
      (list x))
    1]

   [values1
    (let-values ([(x) (f)])
      (list x))
    (values 1)]
   [values2
    (let-values ([(x y) (f)])
      (list x y))
    (values 1 2)]
   [values3
    (let-values ([(x y z) (f)])
      (list x y z))
    (values 1 2 3)]
   [values4
    (let-values ([(x y z a) (f)])
      (list x y z a))
    (values 1 2 3 4)]
   [values5
    (let-values ([(x y z a b) (f)])
      (list x y z a b))
    (values 1 2 3 4 5)]
   [values6
    (let-values ([(x y z a b c) (f)])
      (list x y z a b c))
    (values 1 2 3 4 5 6)]
   [values7
    (let-values ([(x y z a b c d) (f)])
      (list x y z a b c d))
    (values 1 2 3 4 5 6 7)]

   [values+1
    (let-values+ ([(x) (f)])
                 (list x))
    (values+ 1)]
   [values+2
    (let-values+ ([(x y) (f)])
                 (list x y))
    (values+ 1 2)]
   [values+3
    (let-values+ ([(x y z) (f)])
                 (list x y z))
    (values+ 1 2 3)]
   [values+4
    (let-values+ ([(x y z a) (f)])
                 (list x y z a))
    (values+ 1 2 3 4)]
   [values+5
    (let-values+ ([(x y z a b) (f)])
                 (list x y z a b))
    (values+ 1 2 3 4 5)]
   [values+6
    (let-values+ ([(x y z a b c) (f)])
                 (list x y z a b c))
    (values+ 1 2 3 4 5 6)]
   [values+7
    (let-values+ ([(x y z a b c d) (f)])
                 (list x y z a b c d))
    (values+ 1 2 3 4 5 6 7)]

   [values+7kw
    (let-values+ ([(x y z a b c #:d d) (f)])
                 (list x y z a b c d))
    (values+ 1 2 3 4 5 6 #:d 7)]
   [values+7opt
    (let-values+ ([(x y z a b c [d 7]) (f)])
                 (list x y z a b c d))
    (values+ 1 2 3 4 5 6)]
   [values7opt
    (let-values+ ([(x y z a b c [d 7]) (f)])
                 (list x y z a b c d))
    (values 1 2 3 4 5 6)]
   [values+7kwopt
    (let-values+ ([(x y z a b c #:d [d 7]) (f)])
                 (list x y z a b c d))
    (values+ 1 2 3 4 5 6)]
   [values7kwopt
    (let-values+ ([(x y z a b c #:d [d 7]) (f)])
                 (list x y z a b c d))
    (values 1 2 3 4 5 6)]
   [values+7rest
    (let-values+ ([(x . xs) (f)])
                 (cons x xs))
    (values+ 1 2 3 4 5 6 7)]
   [values7rest
    (let-values+ ([(x . xs) (f)])
                 (cons x xs))
    (values 1 2 3 4 5 6 7)]))

;; XXX contracts
(define-syntax (->+ stx)
  (syntax-parse stx
    [(_ (m-e:expr ...)
        ((~literal values+)
         ((~or rm-e:expr
               (~seq rm-kw:keyword rm-kw-e:expr))
          ...)
         (~optional ((~or ro-e:expr
                          (~seq ro-kw:keyword ro-kw-e:expr))
                     ...)
                    #:defaults ([(ro-e 1) null]
                                [(ro-kw 1) null]
                                [(ro-kw-e 1) null]))
         (~optional (~seq #:rest rr-ctc:expr)
                    #:defaults ([rr-ctc #'#f]))))
     (syntax/loc stx
       (let ([ms (list m-e ...)]
             [rms (list rm-e ...)]
             [ros (list ro-e ...)]
             [kw-ms (make-immutable-hasheq (list (cons 'rm-kw rm-kw-e) ...))]
             [kw-os (make-immutable-hasheq (list (cons 'ro-kw ro-kw-e) ...))]
             [rr-ctcv rr-ctc])
         (make-contract
          #:name '->+
          #:first-order procedure?
          #:projection
          (λ (b)
            (λ (f)
              (if (procedure? f)
                (λ args
                  (unless (= (length args) (length ms))
                    (raise-blame-error b args "expected ~e args" (length ms)))
                  (call-with-values+
                   (λ ()
                     (apply f
                            (for/list ([a (in-list args)]
                                       [m (in-list ms)])
                              (((contract-projection m) (blame-swap b)) a))))
                   (make-keyword-procedure
                    (λ (kws kw-res . res)
                      (unless rr-ctcv
                        (unless (<= (length res) (+ (length rms) (length ros)))
                          (raise-blame-error b res "expected ~e plus ~e results, given ~e"
                                             (length rms)
                                             (length ros)
                                             (length res))))
                      (unless (for/and ([kw (in-hash-keys kw-ms)])
                                (member kw kws))
                        (raise-blame-error b kws "expected ~a kw args" kw-ms))
                      (keyword-apply
                       values+
                       kws
                       (for/list ([kw (in-list kws)]
                                  [kw-a (in-list kw-res)])
                         (define ctc
                           (hash-ref kw-ms kw
                                     (λ ()
                                       (hash-ref kw-os kw
                                                 (λ ()
                                                   (raise-blame-error b kw "unexpected kw result ~e" kw))))))
                         (((contract-projection ctc) b) kw-a))
                       (append
                        (for/list ([a (in-list res)]
                                   [m (in-list (append rms ros))])
                          (((contract-projection m) b) a))
                        (if rr-ctcv
                          (((contract-projection rr-ctcv) b) (list-tail res (length rms)))
                          null)))))))
                (raise-blame-error b f "expected procedure")))))))]))

(module+ test
  (require rackunit)

  (define-syntax-rule (ctest c f)
    ((contract c f 'pos 'neg)))
  (define-syntax-rule (cok c f)
    (check-not-exn (λ () (ctest c f))))
  (define-syntax-rule (cbad c f)
    (check-exn exn:fail:contract? (λ () (ctest c f))))
  (define-syntax-rule (cboth x c f)
    (begin
      (cok c ((λ (x) f) #t))
      (cbad c ((λ (x) f) 0))))

  (cboth x (-> boolean?) (λ () x))

  (cboth x (->* () (values boolean?)) (λ () x))

  (cboth x (->+ () (values+ (boolean?))) (λ () x))
  (cbad (->+ () (values+ (boolean?))) (λ () (values+ #f #:a 0)))
  (cboth x (->+ () (values+ (boolean? any/c))) (λ () (values+ x x)))
  (cboth x (->+ () (values+ (any/c boolean?))) (λ () (values+ x x)))
  (cboth x (->+ () (values+ (boolean?) (any/c))) (λ () (values+ x)))
  (cboth x (->+ () (values+ (boolean?) (boolean?))) (λ () (values+ x)))
  (cboth x (->+ () (values+ (boolean?) (any/c))) (λ () (values+ x x)))
  (cboth x (->+ () (values+ (any/c) (boolean?))) (λ () (values+ x x)))

  (cbad (->+ () (values+ (boolean? #:a any/c))) (λ () (values+ #f)))
  (cboth x (->+ () (values+ (boolean? #:a any/c))) (λ () (values+ x #:a x)))
  (cboth x (->+ () (values+ (any/c #:a boolean?))) (λ () (values+ x #:a x)))
  (cboth x (->+ () (values+ (boolean?) (#:a boolean?))) (λ () (values+ x)))
  (cboth x (->+ () (values+ (boolean?) (#:a any/c))) (λ () (values+ x)))
  (cboth x (->+ () (values+ (boolean?) (#:a boolean?))) (λ () (values+ x #:a x)))
  (cboth x (->+ () (values+ (any/c) (#:a boolean?))) (λ () (values+ x #:a x)))

  (cboth x (->+ () (values+ (boolean?) #:rest (listof any/c))) (λ () (values+ x x x)))
  (cboth x (->+ () (values+ (any/c) #:rest (listof boolean?))) (λ () (values+ x x x))))
