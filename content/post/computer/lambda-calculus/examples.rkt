#lang racket

;; 1. Abstraction and application
(define identity (lambda (x) x))
(define K (lambda (x) (lambda (y) x)))

;; 2. Lexical scope: the free y is fixed where add-y is written
(define y 10)
(define (add-y x) (+ x y))

;; 3. A closure carries the bindings of its free variables
(define (make-adder n) (lambda (x) (+ x n)))

;; 4. The operand is evaluated before the body is entered
(define (const-first x y) x)

;; 5. Church booleans
(define ctrue (lambda (x) (lambda (y) x)))
(define cfalse (lambda (x) (lambda (y) y)))
(define (cif p) (lambda (a) (lambda (b) ((p a) b))))
(define (cnot p) ((p cfalse) ctrue))
(define (cand p) (lambda (q) ((p q) p)))
(define (cor p) (lambda (q) ((p p) q)))
(define (to-bool b) ((b #t) #f))

;; 6. Pairs
(define (pair x) (lambda (y) (lambda (sel) ((sel x) y))))
(define (pfirst p) (p (lambda (x) (lambda (y) x))))
(define (psecond p) (p (lambda (x) (lambda (y) y))))

;; 7. Church numerals
(define zero (lambda (f) (lambda (x) x)))
(define (succ n) (lambda (f) (lambda (x) (f ((n f) x)))))
(define (plus m) (lambda (n) (lambda (f) (lambda (x) ((m f) ((n f) x))))))
(define (mult m) (lambda (n) (lambda (f) (m (n f)))))
(define (pow b) (lambda (n) (n b)))
(define (pred n)
  (lambda (f)
    (lambda (x)
      (((n (lambda (g) (lambda (h) (h (g f))))) (lambda (u) x))
       (lambda (u) u)))))
(define (iszero n) ((n (lambda (_) cfalse)) ctrue))
(define (church->int n) ((n add1) 0))
(define (int->church k)
  (if (zero? k) zero (succ (int->church (sub1 k)))))

;; 8. Recursion with a recursive definition
(define (fact n) (if (zero? n) 1 (* n (fact (sub1 n)))))

;; 9. Recursion through self-application and a fixed-point combinator
(define (fact-self-application n)
  ((lambda (self) (self self n))
   (lambda (self k) (if (zero? k) 1 (* k (self self (sub1 k)))))))
(define Z
  (lambda (g)
    ((lambda (x) (g (lambda (v) ((x x) v))))
     (lambda (x) (g (lambda (v) ((x x) v)))))))
(define fact-via-Z
  (Z (lambda (r) (lambda (n) (if (zero? n) 1 (* n (r (sub1 n))))))))

;; 10. Combinators, and abstraction elimination
(define I (lambda (x) x))
(define B (lambda (x) (lambda (y) (lambda (z) (x (y z))))))
(define C (lambda (x) (lambda (y) (lambda (z) ((x z) y)))))
(define W (lambda (x) (lambda (y) ((x y) y))))
(define S (lambda (x) (lambda (y) (lambda (z) ((x z) (y z))))))
(define composition (lambda (f) (lambda (g) (lambda (x) (f (g x))))))

;; 11. A continuation as a value
(define (safe-div a b)
  (call/cc
   (lambda (escape)
     (if (zero? b) (escape 'undefined) (/ a b)))))

;; 12. A tail call reuses the caller's frame
(define (count-down n) (if (zero? n) 'done (count-down (sub1 n))))

(define pair1 ((pair 'a) 'b))
(define two (int->church 2))
(define three (int->church 3))

(define results
  (list (identity 'a)
        ((K 'kept) 'ignored)
        (add-y 1)
        (let ([y 100]) (add-y 1))
        ((make-adder 2) 40)
        (with-handlers ([exn:fail? (lambda (e) 'operand-evaluated)])
          (const-first 'kept (error "operand evaluated")))
        (to-bool (cnot ctrue))
        (to-bool (cnot cfalse))
        (to-bool ((cand ctrue) cfalse))
        (to-bool ((cor cfalse) ctrue))
        (pfirst pair1)
        (psecond pair1)
        (church->int zero)
        (church->int two)
        (church->int ((plus two) three))
        (church->int ((mult two) three))
        (church->int ((pow two) three))
        (church->int (pred three))
        (church->int (pred zero))
        (to-bool (iszero zero))
        (to-bool (iszero two))
        (fact 5)
        (fact-self-application 5)
        (fact-via-Z 5)
        (I 'id)
        (((S K) K) 'skk)
        (((B I) I) 'bii)
        (((C K) 'c) 'k)
        ((W K) 'wk)
        (((composition add1) add1) 40)
        (safe-div 6 3)
        (safe-div 6 0)
        (count-down 3)))

(for ([r results]) (displayln r))
