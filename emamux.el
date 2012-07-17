;;; emamux.el --- tmux manipulation from Emacs

;; Copyright (C) 2012 by Syohei YOSHIDA

;; Author: Syohei YOSHIDA <syohex@gmail.com>
;; URL: https://github.com/syohex/emacs-emamux

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;;; History:
;; Revision 0.1  2012/07/???? syohex
;; Initial version
;;

;;; Code:

(eval-when-compile (require 'cl))

(defgroup emamux nil
  "tmux manipulation from Emacs"
  :group 'emamux)

(defcustom emamux:default-orientation 'vertical
  "Orientation of spliting runner pane"
  :type '(choice (const :tag "Split pane vertial" vertical)
                 (const :tag "Split pane horizonal" horizonal))
  :group 'emamux)

(defcustom emamux:runner-pane-height 20
  "Orientation of spliting runner pane"
  :type  'integer
  :group 'emamux)

(defcustom emamux:use-nearest-pane nil
  "Use nearest pane for runner pane"
  :type  'boolean
  :group 'emamux)

(defvar emamux:last-command nil
  "Last emit command")

(defvar emamux:session nil)
(defvar emamux:window nil)
(defvar emamux:pane nil)

(defun emamux:tmux-running-p ()
  (= (call-process-shell-command "tmux has-session" nil nil nil) 0))

(defun* emamux:tmux-run-command (cmd &optional (output nil))
  (let ((cmd (format "tmux %s" cmd)))
    (unless (= (call-process-shell-command cmd nil output nil) 0)
      (error (format "Failed: %s" cmd)))))

(defun emamux:set-parameters ()
  (progn
    (emamux:set-parameter-session)
    (emamux:set-parameter-window)
    (emamux:set-parameter-pane)))

(defun emamux:unset-parameters ()
  (setq emamux:session nil emamux:window nil emamux:pane nil))

(defun emamux:set-parameters-p ()
  (and emamux:session emamux:window emamux:pane))

(defun emamux:set-parameter-session ()
  (let ((candidates (emamux:get-sessions)))
    (setq emamux:session
          (if (= (length candidates) 1)
              (car candidates)
            (completing-read "Input session: " candidates nil t)))))

(defun emamux:set-parameter-window ()
  (let* ((candidates (emamux:get-window))
         (selected (if (= (length candidates) 1)
                       (car candidates)
                     (completing-read "Input window: " candidates nil t))))
    (setq emamux:window (car (split-string selected ":")))))

(defun emamux:set-parameter-pane ()
  (let ((candidates (emamux:get-pane)))
    (setq emamux:pane
          (if (= (length candidates) 1)
              (car candidates)
            (completing-read "Input pane: " candidates)))))

(defun* emamux:target-session (&optional (session emamux:session)
                                         (window emamux:window)
                                         (pane emamux:pane))
  (format "%s:%s.%s" session window pane))

(defun emamux:get-sessions ()
  (with-temp-buffer
    (emamux:tmux-run-command "list-sessions" t)
    (goto-char (point-min))
    (let (sessions)
      (while (re-search-forward "^\\([^:]+\\):" nil t)
        (push (match-string-no-properties 1) sessions))
      sessions)))

(defun emamux:get-window ()
  (with-temp-buffer
    (emamux:tmux-run-command (format "list-windows -t %s" emamux:session) t)
    (goto-char (point-min))
    (let (windows)
      (while (re-search-forward "^\\([0-9]+: [^ ]+\\)" nil t)
        (push (match-string-no-properties 1) windows))
      (reverse windows))))

(defun emamux:get-pane ()
  (with-temp-buffer
    (emamux:tmux-run-command (format "list-panes -t %s:%s"
                                     emamux:session emamux:window) t)
    (goto-char (point-min))
    (let (panes)
      (while (re-search-forward "^\\([0-9]+\\):" nil t)
        (push (match-string-no-properties 1) panes))
      (reverse panes))))

(defun emamux:read-command (prompt use-last-cmd)
  (read-string prompt (and use-last-cmd emamux:last-command)))

(defun emamux:check-tmux-running ()
  (unless (emamux:tmux-running-p)
    (error "'tmux' does not run on this machine!!")))

(defun emamux:send-command ()
  "Send command to tmux target-session"
  (interactive)
  (emamux:check-tmux-running)
  (condition-case nil
      (progn
        (if (or current-prefix-arg (not (emamux:set-parameters-p)))
            (emamux:set-parameters))
        (let* ((target (emamux:target-session))
               (prompt (format "Send to (%s): " target))
               (input  (read-string prompt emamux:last-command)))
          (emamux:reset-prompt target)
          (emamux:send-keys input)
          (setq emamux:last-command input)))
      (quit (emamux:unset-parameters))))

(defun emamux:escape (input)
  (emamux:escape-quote (emamux:escape-dollar input)))

(defun emamux:escape-quote (input)
  (replace-regexp-in-string "\\\"" "\\\\\"" input))

(defun emamux:escape-dollar (input)
  (replace-regexp-in-string "\\$" "\\\\\$" input))

(defun* emamux:send-keys (input &optional (target (emamux:target-session)))
  (let ((cmd (format "send-keys -t %s \"%s\" C-m"
                     target (emamux:escape input))))
    (emamux:tmux-run-command cmd)))

(defun emamux:send-raw-keys (input target)
  (let ((cmd (format "send-keys -t %s %s" target input)))
    (emamux:tmux-run-command cmd)))

(defun emamux:in-tmux-p ()
  (and (not (display-graphic-p))
       (getenv "TMUX")))

(defvar emamux:runner-pane-id nil)

(defun emamux:run-command (cmd)
  "Run command"
  (interactive
   (list (read-string "Run command: ")))
  (emamux:check-tmux-running)
  (unless (emamux:in-tmux-p)
    (error "You are not in 'tmux'"))
  (let ((current-pane (emamux:active-pane-id)))
    (unless (emamux:runner-alive-p)
      (emamux:setup-runner-pane)
      (emamux:chdir-pane))
    (emamux:send-keys cmd emamux:runner-pane-id)
    (emamux:select-pane current-pane)))

(defun emamux:reset-prompt (pane)
  (emamux:send-raw-keys "q C-u" pane))

(defun emamux:chdir-pane ()
  (let ((chdir-cmd (format " cd %s" default-directory)))
    (emamux:send-keys chdir-cmd emamux:runner-pane-id)))

(defun emamux:setup-runner-pane ()
  (let ((nearest-pane-id (emamux:nearest-inactive-pane-id)))
    (if (and emamux:use-nearest-pane nearest-pane-id)
      (progn
        (emamux:select-pane nearest-pane-id)
        (emamux:reset-prompt nearest-pane-id))
      (emamux:split-runner-pane)))
  (setq emamux:runner-pane-id (emamux:active-pane-id)))

(defun emamux:select-pane (target)
  (let ((cmd (format "select-pane -t %s" target) ))
    (emamux:tmux-run-command cmd)))

(defvar emamux:orientation-option-alist
  '((vertical . "-v") (horizonal . "-h")))

(defun emamux:split-runner-pane ()
  (let ((orient-option (assoc-default emamux:default-orientation
                                      emamux:orientation-option-alist)))
    (emamux:tmux-run-command (format "split-window -p %d %s"
                                     emamux:runner-pane-height orient-option))))

(defun emamux:list-panes ()
  (with-temp-buffer
    (emamux:tmux-run-command "list-panes" t)
    (loop initially (goto-char (point-min))
          while (re-search-forward "^\\(.+\\)$" nil t nil)
          collect (match-string-no-properties 1))))

(defun emamux:active-pane-id ()
  (loop for pane in (emamux:list-panes)
        when (string-match "\\([^ ]+\\) (active)$" pane)
        return (match-string-no-properties 1 pane)))

(defun emamux:nearest-inactive-pane-id ()
  (loop for pane in (emamux:list-panes)
        when (not (string-match "(active)$" pane))
        return (if (string-match " \\([^ ]+\\)$" pane)
                   (match-string-no-properties 1 pane))))

(defun emamux:close-runner-pane ()
  (interactive)
  (emamux:runner-alive-p)
  (emamux:kill-pane emamux:runner-pane-id)
  (setq emamux:runner-pane-id nil))

(defun emamux:close-panes ()
  (interactive)
  (let ((panes (emamux:list-panes)))
    (if (> (length panes) 1)
        (emamux:kill-all-panes))))

(defun emamux:kill-all-panes ()
  (let ((cmd "kill-pane -a"))
    (emamux:tmux-run-command cmd)))

(defun emamux:kill-pane (target)
  (let ((cmd (format "kill-pane -t %s" target)))
    (emamux:tmux-run-command cmd)))

(defun emamux:pane-alive-p (target)
  (let ((cmd (format "tmux list-panes -t %s" target)))
    (= (call-process-shell-command cmd nil nil nil) 0)))

(defun emamux:runner-alive-p ()
  (and emamux:runner-pane-id (emamux:pane-alive-p emamux:runner-pane-id)))

(defun emamux:check-runner-alive ()
  (unless (emamux:runner-alive-p)
    (error "There is no runner pane")))

(defun emamux:inspect-runner ()
  (interactive)
  (emamux:check-runner-alive)
  (emamux:select-pane emamux:runner-pane-id)
  (emamux:tmux-run-command "copy-mode"))

(defun emamux:interrupt-runner ()
  (interactive)
  (emamux:check-runner-alive)
  (emamux:send-raw-keys "^c" emamux:runner-pane-id))

(defun emamux:clear-runner-history ()
  (interactive)
  (emamux:check-runner-alive)
  (emamux:tmux-run-command (format "clear-history %s" emamux:runner-pane-id)))

;;; emamux.el ends here
