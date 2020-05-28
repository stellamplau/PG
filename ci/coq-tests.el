;;; coq-tests.el --- integration tests -*- lexical-binding: t; -*-

;;; Commentary:
;;

;;;  Eval this to run the tests interactively <C-x C-e>
;;
;; (progn (load-file "coq-tests.el") (call-interactively #'ert))

(unless (and (boundp 'coq-test-dir) coq-test-dir) ; if set by ./test.sh
  (if buffer-file-name
      (setq coq-test-dir (file-name-directory buffer-file-name))
    (error "You should set 'coq-test-dir, or run coq-test.el from a file buffer.")))

(setq debug-on-error t) ; open the debugger on error -- may be commented-out
(setq ert-batch-backtrace-right-margin 79)

(require 'subr-x) ;; for (string-trim)
;;(require 'ert-async)
;;(setq ert-async-timeout 2)

;;; Code:

; Exemple de code Lisp qui lance des commandes au prouveur en arrière-plan
; (defun has-error ()
;   "True if error in Proof"
;   (eq 'error proof-shell-last-output-kind))
; 
; (defun test-process-invisible-split ()
;   (proof-shell-invisible-command "split."
;    'waitforit
;     #'proof-done-invisible
;     'no-error-display 'no-response-display 'no-goals-display))
; 
; (defun test-process-invisible-tactics-then-reset-and-insert ()
;   (interactive)
;   (let ((reset-cmd ; store backtracking info before proof search
;            (format "Backtrack %s %s %s . "
;                    (int-to-string coq-last-but-one-statenum)
;                    (int-to-string coq-last-but-one-proofnum)
;                    0)))
;          ;; Toy example of proof search
;          (while (not (has-error))
;                 (message "Trying split.")
;                 (test-process-invisible-split))
;          ;; Reset to the previous state
;          (proof-shell-invisible-command reset-cmd 'waitforit #'proof-done-invisible)
;          ;; Insert (and re-process) the found script
;          (proof-insert-sendback-command "split.\nsplit.\nsplit.\nQed.")))
; 
; (test-process-invisible-tactics-then-reset-and-insert)

(defun coq-test-full-path (basename)
  "Return the absolute path of BASENAME (a filename such as ./foo.v)."
  (concat coq-test-dir basename))

(defconst coq-test-file-prefix "coq_test_")

(defun coq-test-init ()
  "Ensure `coq' is loaded."
  (unless (featurep 'coq)
    (add-to-list 'load-path
		 (locate-dominating-file coq-test-dir "proof-general.el"))
    (load "proof-general")
    (proofgeneral "coq")))

(defun coq-test-exit ()
  "Exit the Coq process."
  (proof-shell-exit t))

; (coq-test-on-file nil (message (buffer-file-name)) (message "OK") 42)

;; DEFINITION OF MOCKS, SEE `coq-mock' BELOW
;; Another solution would consist in using el-mock, mentioned in:
;; https://www.gnu.org/software/emacs/manual/html_mono/ert.html#Mocks-and-Stubs
(defun coq-mock-proof-display-three-b (&rest rest)
  (message (concat "Skipping proof-display-three-b on input: "
                   (pp-to-string rest)))
  ; Result:
  nil)

;; AVOID THE FOLLOWING ERROR:
;; Hit M-x proof-layout-windows to reset layout
;; Debugger entered--Lisp error: (error "Window #<window 6 on *goals*> too small for splitting")
;;   signal(error ("Window #<window 6 on *goals*> too small for splitting"))
;;   error("Window %s too small for splitting" #<window 6 on *goals*>)
;;   split-window(nil nil)
;;   split-window-vertically()
;;   proof-safe-split-window-vertically()
;;   proof-select-three-b(nil #<buffer *goals*> #<buffer *response*> smart)
;;   proof-display-three-b(smart)
;;   proof-layout-windows()
;;   proof-multiple-frames-enable()
;;   proof-shell-start()
;;   proof-shell-ready-prover()
(defun coq-mock (f)
  (require 'pg-response) ; load the feature defining proof-display-three-b first
   (cl-letf (;((symbol-function 'foo) #'mock-foo)
             ((symbol-function 'proof-display-three-b) #'coq-mock-proof-display-three-b))
     (funcall f)))
;; Run <C-x C-e> on:
;; (coq-mock #'main)

(defun coq-test-cmd (cmd)
  ;;(coq-test-on-file)
  ;;(coq-test-init)
  (proof-shell-invisible-command
   cmd
   'waitforit
   #'proof-done-invisible
   'no-error-display 'no-response-display 'no-goals-display))

(defun coq-set-flags (val flags)
  (when (member 'show-proof-stepwise flags) (setq coq-show-proof-stepwise val))
  (when (member 'diffs-on flags) (if val (setq coq-diffs 'on) (setq coq-diffs 'off)))
  )


(defun coq-fixture-on-file (file  body &rest flags)
  "Fixture to setup the test env: open FILE if non-nil, or a temp file
then evaluate the BODY function and finally tear-down (exit Coq)."
;; AVOID THE FOLLOWING ERROR:
;; Starting:  -emacs
;; Debugger entered--Lisp error: (wrong-type-argument stringp nil)
;;   file-name-directory(nil)
;;   scomint-exec-1("coq" #<buffer *coq*> nil ("-emacs"))
;;   scomint-exec(#<buffer *coq*> "coq" nil nil ("-emacs"))
;;   scomint-make-in-buffer("coq" nil nil nil "-emacs")
;;   apply(scomint-make-in-buffer "coq" nil nil nil "-emacs")
;;   scomint-make("coq" nil nil "-emacs")
;;   apply(scomint-make ("coq" nil nil "-emacs"))
;;   proof-shell-start()
;;   proof-shell-ready-prover()
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; For info on macros: https://mullikine.github.io/posts/macro-tutorial
;;; (pp (macroexpand '(macro args)))
  (save-excursion
    (let* ((openfile (or file
                         (concat (make-temp-file coq-test-file-prefix) ".v")))
           ;; if FILE is nil, create a temporary Coq file, removed in the end
           (rmfile (unless file openfile))
           (buffer (find-file openfile)))    
      (message "Opening file %s ..." openfile)
      (unwind-protect
          (progn
            (coq-test-init)
            (with-current-buffer buffer
              (setq proof-splash-enable nil)
              (normal-mode) ;; or (coq-mode)
	      (coq-set-flags t flags)
              (coq-mock body))))
      (coq-test-exit)
      (coq-set-flags nil flags)
      (not-modified nil) ; Clear modification  
      (kill-buffer buffer) 
      (when rmfile (message "Removing file %s ..." rmfile))
      (ignore-errors (delete-file rmfile)))))

(defun coq-test-goto-before (comment)
  "Go just before COMMENT (a unique string in the .v file).
For example, COMMENT could be (*test-definition*)"
  (goto-char (point-max))
  (search-backward comment))

(defun coq-test-goto-after (comment)
  "Go just before COMMENT (a unique string in the .v file)."
  (goto-char (point-min))
  (search-forward comment))

(defun coq-should-response (message)
  (should (equal message
		 (string-trim
                  (with-current-buffer "*response*"
                    (buffer-substring-no-properties (point-min) (point-max)))))))

(defun coq-should-buffer (message)
  (should (string-match-p message
		 (string-trim
                  (with-current-buffer "*coq*"
                    (buffer-substring-no-properties (point-min) (point-max)))))))

;; TODO: Use https://github.com/rejeep/ert-async.el
;; and/or ERT https://www.gnu.org/software/emacs/manual/html_node/ert/index.html

(ert-deftest 010_coq-test-running ()
  "Test that the coqtop process is started properly."
  (coq-fixture-on-file nil 
   (lambda ()
     (coq-test-cmd "Print 0.")
     ;; (should (process-list)) ; wouldn't be a strong enough assert.
     (should (get-process "coq")))))


(ert-deftest 020_coq-test-definition ()
  "Test *response* output after asserting a Definition."
  (coq-fixture-on-file 
   (coq-test-full-path "test_stepwise.v") 
   (lambda ()
     (coq-test-goto-before "(*test-definition*)")
     (proof-goto-point)
     (proof-shell-wait)
     (coq-should-response "trois is defined"))))


(ert-deftest 021_coq-test-regression-goto-point ()
  "Regression test for proof-goto-point after a comment, PR #90"
  (coq-fixture-on-file 
   (coq-test-full-path "test_stepwise.v") 
   (lambda ()
       (coq-test-goto-after "(*test-definition*)")
       (proof-goto-point)
       (proof-shell-wait)
       t)))


(ert-deftest 030_coq-test-position ()
  "Test locked region after Qed."
  (coq-fixture-on-file 
   (coq-test-full-path "test_stepwise.v") 
   (lambda ()
     (coq-test-goto-before " (*test-lemma*)")
     (let ((proof-point (point)))
     (proof-goto-point)
     (proof-shell-wait)
     (should (equal (proof-queue-or-locked-end) proof-point))))))


(ert-deftest 040_coq-test-insert ()
  "Test retract on insert from Qed."
  (coq-fixture-on-file 
   (coq-test-full-path "test_stepwise.v") 
   (lambda ()
     (coq-test-goto-before " (*test-lemma*)")
     (proof-goto-point)
     (proof-shell-wait)
     (let ((proof-point (point)))
       (coq-test-goto-before "(*test-insert*)")
       (move-beginning-of-line nil)
       (insert "\n")
       ;; The locked end point should go up compared to before 
       (should (< (proof-queue-or-locked-end) proof-point))))))


(ert-deftest 050_coq-test-lemma-false ()
  "Test retract on proof error."
  (coq-fixture-on-file 
   (coq-test-full-path "test_stepwise.v") 
   (lambda ()
     (coq-test-goto-before " (*test-lemma2*)")
     (let ((proof-point (save-excursion (coq-test-goto-after "(*error*)")))) 
     (proof-goto-point)
     (proof-shell-wait)
     (coq-should-response "Error: Unable to unify \"false\" with \"true\".")
     (should (equal (proof-queue-or-locked-end) proof-point))))))


(ert-deftest 060_coq-test-wholefile ()
  "Test `proof-process-buffer'."
  (coq-fixture-on-file
   (coq-test-full-path "test_wholefile.v")
   (lambda ()
     (let ((proof-point (save-excursion
			  (coq-test-goto-before "Theorem")
			  (search-forward "Qed."))))
     (proof-process-buffer)
     (proof-shell-wait)
     (should (equal (proof-queue-or-locked-end) proof-point))))))


(ert-deftest 070_coq-test-regression-wholefile-no-proof ()
  "Regression test for no proof bug"
  (coq-fixture-on-file 
   (coq-test-full-path "test_wholefile.v") 
   (lambda ()
     (proof-process-buffer)
     (proof-shell-wait)
     (goto-char (point-min))
     (insert "(*.*)")
     (should (equal (proof-queue-or-locked-end) 1)))))

(ert-deftest 080_coq-test-regression-show-proof-stepwise()
  "Regression test for the \"Show Proof\" option"
    (coq-fixture-on-file 
   (coq-test-full-path "test_stepwise.v") 
   (lambda ()
     (coq-test-goto-before " (*test-insert*)")
     (proof-goto-point)
     (proof-shell-wait)
     (coq-should-response "(fun (A : Prop) (proof_of_A : A) => ?Goal)"))
   'show-proof-stepwise))


(ert-deftest 081_coq-test-regression-show-proof-diffs()
  "Test for Show Proof Diffs"
    (coq-fixture-on-file 
   (coq-test-full-path "test_stepwise.v") 
   (lambda ()
     (coq-test-goto-before " (*test-insert*)")
     (proof-goto-point)
     (proof-shell-wait)
     ;; If coq--post-v811, it should be "Show Proof Diffs." otherwise "Show Proof."
     (if (coq--post-v811)
	 (coq-should-buffer  "<diff\\.added\\.bg>(fun <diff\\.added>(</diff\\.added>A : Prop<diff\\.added>) (proof_of_A : A)</diff\\.added> => \\?Goal)</diff\\.added\\.bg>")
       (coq-should-buffer "(fun (A : Prop) (proof_of_A : A) => \\?Goal)")))
   'show-proof-stepwise 'diffs-on))
 

(provide 'coq-tests)

;;; coq-tests.el ends here
