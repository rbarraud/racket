#lang racket/base

(require (for-syntax racket/base))

(provide test-multi-sequence
         test-sequence)

;; Utilities used by various tests of sequences

(define-syntax (test-multi-sequence stx)
  (syntax-case stx ()
    [(_ [(v ...) ...] gen)
     (with-syntax ([(id ...) (generate-temporaries #'((v ...) ...))]
                   [(id2 ...) (generate-temporaries #'((v ...) ...))]
                   [((v2 ...) ...)
                    (apply map list (map syntax->list (syntax->list #'((v ...) ...))))])
       #'(begin
           (test `((v2 ...) ...) 'gen (for/list ([(id ...) gen])
                                        (list id ...)))
           (test-values `((v ...) ...) (lambda ()
                                         (for/lists (id2 ...) ([(id ...) gen])
                                           (values id ...))))
           (test #t 'gen (for/and ([(id ...) gen])
                           (and (member (list id ...) `((v2 ...) ...)) #t)))
           (test (list (for/last ([(id ...) gen])
                         (list id ...)))
                 'gen (for/and ([(id ...) gen])
                         (member (list id ...) `((v2 ...) ...))))
           (test (for/first ([(id ...) gen])
                   (list id ...))
                 'gen (for/or ([(id ...) gen])
                         (car (member (list id ...) `((v2 ...) ...)))))
           (void)))]))

;; Tests use `for/list`, but plain `for` may compile differently:
(define-syntax-rule (for/list~ binds expr)
  (let ([l null])
    (for binds (set! l (cons expr l)))
    (reverse l)))
(define-syntax-rule (for*/list~ binds expr)
  (let ([l null])
    (for* binds (set! l (cons expr l)))
    (reverse l)))

(define-syntax test-sequence
  (syntax-rules ()
    [(_ [seq] gen) ; we assume that seq has at least 2 elements, and all are unique
     (begin
       ;; Some tests specific to single-values:
       (test `seq 'gen (for/list ([i gen]) i))
       (test `seq 'gen (for/list~ ([i gen]) i))
       (test `seq 'gen (for/list ([i gen][b gen]) i))
       (test `seq 'gen (for/list~ ([i gen][b gen]) i))
       (test `seq 'gen (for/list ([i gen][b gen]) b))
       (test `seq 'gen (for/list~ ([i gen][b gen]) b))
       (test `seq 'gen (for*/list ([i gen][b '(#t)]) i))
       (test (map (lambda (x) #t) `seq) 'gen (for*/list ([i gen][b '(#t)]) b))
       (test (append `seq `seq) 'gen (for*/list ([b '(#f #t)][i gen]) i))
       (test (append `seq `seq) 'gen (for*/list~ ([b '(#f #t)][i gen]) i))
       (test (append `seq `seq) 'gen (for/list ([b '(#f #t)] #:when #t [i gen]) i))
       (test (append `seq `seq) 'gen (for/list~ ([b '(#f #t)] #:when #t [i gen]) i))
       (test (append `seq `seq) 'gen (for/list ([b '(#t #t #f)] #:when b [i gen]) i))
       (test (append `seq `seq) 'gen (for/list~ ([b '(#t #t #f)] #:when b [i gen]) i))
       (test (append `seq `seq) 'gen (for/list ([b '(#f #t)] #:unless #f [i gen]) i))
       (test (append `seq `seq) 'gen (for/list~ ([b '(#f #t)] #:unless #f [i gen]) i))
       (test (append `seq `seq) 'gen (for/list ([b '(#f #f #t)] #:unless b [i gen]) i))
       (test (append `seq `seq) 'gen (for/list~ ([b '(#f #f #t)] #:unless b [i gen]) i))
       (test `seq 'gen (let ([g gen]) (for/list ([i g]) i)))
       (test `seq 'gen (let ([r null])
                         (for ([i gen]) (set! r (cons i r)))
                         (reverse r)))
       (test `seq 'gen (reverse (for/fold ([a null]) ([i gen]) 
                                  (cons i a))))
       (test `seq 'gen (let-values ([(more? next) (sequence-generate gen)])
                         (let loop ()
                           (if (more?)
                               (cons (next) (loop))
                               null))))
       (test-values `(seq seq) (lambda ()
                                 (for/lists (r1 r2) ([id gen])
                                   (values id id))))
       (test (list (for/last ([i gen]) i)) 'gen (for/and ([i gen]) (member i `seq)))
       (test `seq 'gen (for/or ([i gen]) (member i `seq)))
       (test (for/first ([i gen]) i) 'gen (for/or ([i gen]) (and (member i `seq) i)))
       (test (for/sum ([i gen]) (if (number? i) i 0)) 'gen 
             (for/fold ([n 0]) ([i gen]) (if (number? i) (+ i n) n)))
       (test (for/product ([i gen]) (if (number? i) i 1)) 'gen 
             (for/fold ([n 1]) ([i gen]) (if (number? i) (* i n) n)))
       (test #t 'gen (for/and ([(i k) (in-parallel gen `seq)])
                       (equal? i k)))
       (test #f 'gen (for/and ([i gen])
                       (member i (cdr (reverse `seq)))))
       (test #f 'gen (for/or ([i gen]) (equal? i 'something-else)))
       (let ([count 0])
         (test #t 'or (for/or ([i gen]) (set! count (add1 count)) #t))
         (test 1 'count count)
         (test #f 'or (for/or ([i gen]) (set! count (add1 count)) #f))
         (test (+ 1 (length `seq)) 'count count)
         (set! count 0)
         (let ([second (for/last ([(i pos) (in-parallel gen (in-naturals))] #:when (< pos 2))
                         (set! count (add1 count))
                         i)])
           (test second list-ref `seq 1)
           (test 2 values count)
           (for ([i gen] #:when (equal? i second)) (set! count (add1 count)))
           (for* ([i gen] #:when (equal? i second)) (set! count (add1 count)))
           (test 4 values count)
           (for ([i (stop-before gen (lambda (x) (equal? x second)))]) (set! count (add1 count)))
           (test 5 values count)
           (let ([g (stop-before gen (lambda (x) (equal? x second)))])
             (for ([i g]) (set! count (add1 count))))
           (test 6 values count)
           (for ([i (stop-after gen (lambda (x) (equal? x second)))]) (set! count (add1 count)))
           (test 8 values count)
           (let ([g (stop-after gen (lambda (x) (equal? x second)))])
             (for ([i g]) (set! count (add1 count))))
           (test 10 values count))
         (set! count 0)
         (test #t 'and (for/and ([(e idx) (in-indexed gen)]) (set! count (add1 count)) (equal? idx (sub1 count))))
         (test #t 'and (let ([g (in-indexed gen)])
                         (set! count 0)
                         (for/and ([(e idx) g]) (set! count (add1 count)) (equal? idx (sub1 count)))))
         (void))
       ;; Run multi-value tests:
       (test-multi-sequence [seq] gen))]
    [(_ seqs gen)
     (test-multi-sequence seqs gen)]))
