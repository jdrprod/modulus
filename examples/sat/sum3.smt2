(set-logic ALL)
(declare-const w Int)
(declare-const x Int)
(declare-const y Int)
(declare-const z Int)
(assert (= y 3))
(assert (= (+ w x) (+ y z)))
(check-sat)
(get-model)