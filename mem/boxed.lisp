;; -*- lisp -*-

;; This file is part of Hyperluminal-mem.
;; Copyright (c) 2013-2015 Massimiliano Ghilardi
;;
;; This library is free software: you can redistribute it and/or
;; modify it under the terms of the Lisp Lesser General Public License
;; (http://opensource.franz.com/preamble.html), known as the LLGPL.
;;
;; This library is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty
;; of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
;; See the Lisp Lesser General Public License for more details.


(in-package :hyperluminal-mem)

(enable-#?-syntax)


(defun box-words/unallocated (index value)
  (declare (ignore index value))
  (error "internal error! attempt to write boxed-type +MEM-BOX/UNALLOCATED+"))

(defun mwrite-box/unallocated (ptr index value)
  (declare (ignore ptr index value))
  (error "internal error! attempt to write boxed-type +MEM-BOX/UNALLOCATED+"))

(defun mread-box/unallocated (ptr index)
  (declare (ignore ptr index))
  (error "internal error! attempt to read boxed-type +MEM-BOX/UNALLOCATED+"))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;    dispatchers for all boxed types                                      ;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


(declaim (type vector +msize-box-funcs+ +mwrite-box-funcs+ +mread-box-funcs+))

(defmacro define-global-constant (name value &optional documentation)
  `(#+(and) defparameter #-(and) define-constant-once
      ,name ,value
      ,@(when documentation `(,documentation))))


(define-global-constant +msize-box-funcs+
    (let* ((syms +mem-boxed-type-syms+)
           (array (make-array (length syms))))

      (loop for i from 0 below (length syms) do
           (setf (svref array i) (fdefinition (concat-symbols 'box-words/ (svref syms i)))))
      array))


(define-global-constant +mwrite-box-funcs+
    (let* ((syms +mem-boxed-type-syms+)
            (array (make-array (length syms))))

       (loop for i from 0 below (length syms) do
            (setf (svref array i) (fdefinition (concat-symbols 'mwrite-box/ (svref syms i)))))
       array))


(define-global-constant +mread-box-funcs+
    (let* ((syms +mem-boxed-type-syms+)
           (array (make-array (length syms))))

      (loop for i from 0 below (length syms) do
           (setf (svref array i) (fdefinition (concat-symbols 'mread-box/ (svref syms i)))))
      array))



(declaim (inline get-box-func))

(defun get-box-func (funcs boxed-type)
  (declare (type vector funcs)
           (type mem-box-type boxed-type))

  (let ((i (- boxed-type +mem-box/first+)))
    (the function (svref funcs i))))



(defmacro call-box-func (funcs boxed-type &rest args)
  `(progn
     #-(and) (log:debug 'funcall ,boxed-type ,@args)
     (funcall (get-box-func ,funcs ,boxed-type) ,@args)))


(declaim (notinline mdetect-box-type))

(defun mdetect-box-type (value)
  "Detect the boxed-type of VALUE. Returns one of the constants +mem-box/...+"

  (the (or null mem-box-type)
    (typecase value
      (integer      +mem-box/bignum+)
      (ratio        +mem-box/ratio+)

      (single-float +mem-box/sfloat+)
      (double-float +mem-box/dfloat+)

      ((complex single-float) +mem-box/complex-sfloat+)
      ((complex double-float) +mem-box/complex-dfloat+)
      (complex      (etypecase (realpart value)
                      (rational     +mem-box/complex-rational+)))

      (list         +mem-box/list+)

      (array        (if (/= 1 (array-rank value))
                        +mem-box/array+
                        (case (array-element-type value)
                          (character +mem-box/string+)
                          (base-char +mem-box/base-string+)
                          (bit       +mem-box/bit-vector+)
                          (otherwise +mem-box/vector+))))
      
      (symbol       +mem-box/symbol+) ;; it would be the last one... out of order for speed.

      (hash-table   (ecase (hash-table-test value)
                      ((eq    #+clisp ext:fasthash-eq)      +mem-box/hash-table-eq+)
                      ((eql   #+clisp ext:fasthash-eql)     +mem-box/hash-table-eq+)
                      ((equal #+clisp ext:fasthash-equal)   +mem-box/hash-table-equal+)
                      ((equalp)                             +mem-box/hash-table-equal+)))
                              
      (pathname     +mem-box/pathname+))))


(declaim (inline round-up-size))

(defun round-up-size (n-words)
  "Round up N-WORDS to a multiple of +MEM-BOX/MIN-WORDS+"
  (declare (type mem-size n-words))

  (logand (mem-size+ n-words #.(1- +mem-box/min-words+))
	  #.(lognot (1- +mem-box/min-words+))))


(declaim (notinline msize-box))

(defun msize-box (index value &optional (boxed-type (mdetect-box-type value)))
  "Return the number of words needed to store boxed VALUE in memory,
also including BOX header.
Does NOT round up the returned value to a multiple of +MEM-BOX/MIN-WORDS+"

  (declare (type mem-size index)
           (type mem-box-type boxed-type))

  #-(and) (log:trace value boxed-type)

  (call-box-func +msize-box-funcs+ boxed-type 
                 (mem-size+ +mem-box/header-words+ index) value))


(declaim (inline msize-box-rounded-up))

(defun msize-box-rounded-up (value &optional
                             (boxed-type (mdetect-box-type value)))
  "Return the number of words needed to store boxed VALUE in memory,
also including BOX header.
Rounds up the returned value to a multiple of +MEM-BOX/MIN-WORDS+"

  (declare (type mem-box-type boxed-type))

  (round-up-size (msize-box 0 value boxed-type)))




(declaim (ftype (function (maddress mem-size mem-size t mem-box-type)
			  (values mem-size &optional))
		 mwrite-box)
	 (notinline mwrite-box))

(defun mwrite-box (ptr index end-index value boxed-type)
  "Write a boxed value into the mmap memory starting at (PTR+INDEX).
Also writes BOX header. Returns INDEX pointing to immediately after written value."
  (declare (type maddress ptr)
           (type mem-size index end-index)
           (type mem-box-type boxed-type))

  ;; write BOX payload.
  (let* ((new-index
          (call-box-func +mwrite-box-funcs+ boxed-type ptr
                         (mem-size+ index +mem-box/header-words+)
                         end-index value))
         (actual-words (mem-size- new-index index)))
         
    (when (> new-index end-index)
      (error "HYPERLUMINAL-MEM internal error!
wrote ~S word~P at address ~S + ~S,
but only ~S words were available at that location.
Either this is a bug in hyperluminal-mem, or some object
was concurrently modified while being written"
             actual-words actual-words ptr index (mem-size- end-index index)))

    (mwrite-box/header ptr index boxed-type (round-up-size actual-words))
    new-index))






(declaim (inline %mread-box)
         (notinline mread-box2 mread-box))

(defun %mread-box (ptr index end-index boxed-type)
  "Read a boxed value from the memory starting at (PTR+INDEX) and return it.
Return the number of words actually read as additional value.
Skips over BOX header."
  (declare (type maddress ptr)
           (type mem-size index end-index)
           (type mem-fulltag boxed-type))

  (call-box-func +mread-box-funcs+ boxed-type ptr
                 (mem-size+ index +mem-box/header-words+) end-index))


         


(defun mread-box2 (ptr index end-index boxed-type)
  "Read a boxed value from the memory starting at (PTR+INDEX).
Return the value and the number of words actually read as multiple values."
  (declare (type maddress ptr)
           (type mem-size index)
           (type mem-fulltag boxed-type))

  (check-box-type ptr index boxed-type)

  (%mread-box ptr index end-index boxed-type))


(defun mread-box (ptr index end-index)
  "Read a boxed value from the memory starting at (PTR+INDEX).
Return the value and the number of words actually read as multiple values."
  (declare (type maddress ptr)
           (type mem-size index))
  
  (multiple-value-bind (boxed-type n-words) (mread-box/header ptr index)
    ;; each BOX consumes at least header space + 1 word for payload.
    (let ((min-words #.(1+ +mem-box/header-words+)))

      (setf n-words (max n-words min-words))
      (check-box-type ptr index boxed-type)
      (check-mem-length ptr index end-index n-words)

      (setf end-index (min end-index (mem-size+ index n-words)))
        
      (%mread-box ptr index end-index boxed-type))))








;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;; mid-level functions accepting both boxed and unboxed values             ;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (declaim (ftype (...) msize)) is in box.lisp

(defun msize (index value)
  "Compute and return the number of CPU words needed to store VALUE.
If VALUE can be stored unboxed, returns 1. Otherwise forwards the call
to MSIZE-BOX or, for user-defined types, to MSIZE-OBJECT.
Does NOT round up the returned value to a multiple of +MEM-BOX/MIN-WORDS+"
  (declare (type mem-size index))

   (if (is-unboxed? value)
       (mem-size+1 index)
       (if-bind box-type (mdetect-box-type value)
           (msize-box index value box-type)
           (msize-obj index value))))


(defun msize-rounded-up (index value)
  "Compute and return the number of CPU words needed to store VALUE.
If VALUE can be stored unboxed, returns 1. Otherwise forwards the call
to MSIZE-BOX or, for user-defined types, to MSIZE-OBJECT.
Also rounds up the returned value to a multiple of +MEM-BOX/MIN-WORDS+"
  (declare (type mem-size index))

  (round-up-size (msize index value)))


;; (declaim (ftype (...) mwrite)) is in box.lisp

;; note: unlike MWRITE-OBJECT, VALUE is last argument
(defun mwrite (ptr index end-index value)
  "Write a value (boxed, unboxed or object) into the memory starting at (PTR+INDEX).
Return the INDEX pointing to immediately after the value just written.

WARNING: enough memory must be already allocated at (PTR+INDEX) !!!"
  (declare (type maddress ptr)
           (type mem-size index end-index)
           (type t value))

  (check-mem-overrun ptr index end-index 1)

  (if (mset-unboxed ptr index value)
      (mem-size+1 index)
      (if-bind box-type (mdetect-box-type value)
          (mwrite-box ptr index end-index value box-type)
          (mwrite-obj ptr index end-index value))))


;; (declaim (ftype (...) mread)) is in box.lisp

(defun mread (ptr index end-index)
  "Read a value (boxed, unboxed or object) from the memory starting at (PTR+INDEX).
Return multiple values:
1) the value 
2) the INDEX pointing to immediately after the value just read"
  (declare (type maddress ptr)
           (type mem-size index end-index))

  (check-mem-length ptr index end-index 1)

  (multiple-value-bind (value boxed-type) (mget-unboxed ptr index)
    (unless boxed-type
      (return-from mread (values value (mem-size+1 index))))

    (let* ((n-words (box-pointer->size value))
           (end-box (mem-size+ index n-words))
           (end-index (min end-index end-box)))
      (if (<= (the fixnum boxed-type) +mem-box/last+)
          (mread-box2 ptr index end-index boxed-type)
          (mread-obj ptr index end-index)))))


(defun !mwrite (ptr index value)
  "Used only for debugging."
  (declare (type maddress ptr)
           (type mem-size index))

  (mwrite ptr index +mem-box/max-words+ value))

(defun !mread (ptr index)
  "Used only for debugging."
  (declare (type maddress ptr)
           (type mem-size index))
  (mread ptr index +mem-box/max-words+))
