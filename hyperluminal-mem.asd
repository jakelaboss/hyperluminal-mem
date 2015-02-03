;; -*- lisp -*-

;; This file is part of HYPERLUMINAL-MEM.
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




(in-package :cl-user)

(asdf:defsystem :hyperluminal-mem
  :name "HYPERLUMINAL-MEM"
  :version "0.6.0"
  :license "LLGPL"
  :author "Massimiliano Ghilardi"
  :description "High-performance serialization library, designed for untrusted data"

  :depends-on (#-abcl :cffi
               #-abcl :osicat
               :stmx)

  :components
  ((:static-file "hyperluminal-mem.asd")
	       
   (:module :lang
    :components ((:file "package")
		 (:file "lang"           :depends-on ("package"))))
                  

   (:module :ffi
    :components ((:file "package")
		 (:file "ffi"            :depends-on ("package"))
		 (:file "struct"         :depends-on ("ffi"))
		 (:file "os"             :depends-on ("ffi")))
    :depends-on (:lang))
                  
                               
   #+(and sbcl (or x86 x86-64 #|... other archs here ...|#))
   (:module :sbcl
    :components ((:file "package")
		 (:file "compiler"       :depends-on ("package"))
		 #+(or x86 x86-64)
		 (:file "x86"            :depends-on ("compiler")))
    :depends-on (:lang :ffi))
                  
   (:module :mem
    :components ((:file "package")
		 (:file "lang"           :depends-on ("package"))
		 (:file "version"        :depends-on ("lang"))
		 (:file "defs"           :depends-on ("lang"))
		 (:file "mem"            :depends-on ("defs"))
		 (:file "ffi-late"       :depends-on ("mem"))
		 (:file "constants"      :depends-on ("ffi-late"))
		 (:file "symbols"        :depends-on ("constants"))
		 (:file "unboxed"        :depends-on ("symbols"))
		 (:file "box"            :depends-on ("version" "unboxed"))
		 (:file "magic"          :depends-on ("box"))
		 
		 (:file "box/bignum"     :depends-on ("box"))
		 (:file "box/ratio"      :depends-on ("box/bignum"))
		 (:file "box/float"      :depends-on ("box"))
		 (:file "box/complex"    :depends-on ("box/float" "box/ratio"))
		 (:file "box/pathname"   :depends-on ("box"))
		 (:file "box/hash-table" :depends-on ("box"))
		 (:file "box/list"       :depends-on ("box"))
		 (:file "box/array"      :depends-on ("box"))
		 (:file "box/vector"     :depends-on ("box/array"))
		 (:file "box/string-utf-21" :depends-on ("box/vector"))
		 (:file "box/string-utf-8"  :depends-on ("box/vector"))
		 (:file "box/string-base"   :depends-on ("box/vector"))
		 (:file "box/bit-vector" :depends-on ("box/vector"))
		 (:file "box/symbol"     :depends-on ("box"))

		 (:file "mvar"           :depends-on ("box"))
		 (:file "struct"         :depends-on ("mvar"))
		 (:file "object"         :depends-on ("struct"))
		 (:file "object/gmap"    :depends-on ("object"))
		 (:file "object/ghash-table" :depends-on ("object"))
		 (:file "object/tcell"   :depends-on ("object"))
		 (:file "object/tstack"  :depends-on ("object"))

		 (:file "boxed"          :depends-on ("box"
						      "box/bignum"
						      "box/ratio"
						      "box/float"
						      "box/complex"
						      "box/pathname"
						      "box/hash-table"
						      "box/list"
						      "box/array"
						      "box/vector"
						      "box/string-utf-21"
						      "box/string-utf-8"
						      "box/string-base"
						      "box/bit-vector"
						      "box/symbol"
						      "object")))
    :depends-on (:lang :ffi
		 #+(and sbcl (or x86 x86-64)) :sbcl))))



(asdf:defsystem :hyperluminal-mem.test
  :name "HYPERLUMINAL-MEM.TEST"
  :version "0.6.0"
  :author "Massimiliano Ghilardi"
  :license "LLGPL"
  :description "test suite for hyperluminal-mem"

  :depends-on (:log4cl
               :fiveam
               :hyperluminal-mem)

  :components ((:module :test
                :components ((:file "package")
                             (:file "magic"         :depends-on ("package"))
                             (:file "mem"           :depends-on ("package"))
                             (:file "abi"           :depends-on ("mem"))
                             (:file "stmx-objects"  :depends-on ("abi"))))))


(defmethod asdf:perform ((op asdf:test-op) (system (eql (asdf:find-system :hyperluminal-mem))))
  (asdf:load-system :hyperluminal-mem.test)
  (eval (read-from-string "(fiveam:run! 'hyperluminal-mem.test:suite)")))
