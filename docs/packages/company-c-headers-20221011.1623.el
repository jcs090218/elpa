;;; company-c-headers.el --- Company mode backend for C/C++ header files  -*- lexical-binding: t -*-

;; Copyright (C) 2014 Alastair Rankine
;; Copyright (C) 2022 Jen-Chieh Shen

;; Author: Alastair Rankine <alastair@girtby.net>
;; Maintainer: Jen-Chieh Shen <jcs090218@gmail.com>
;; Keywords: convenience development company
;; Package-Version: 20221011.1623
;; Package-Commit: e9c25243b992fd8ad822312549b3844d45e7936a
;; URL: http://github.com/elp-revive/company-c-headers
;; Package-Requires: ((emacs "26.1") (company "0.8") (f "0.20.0"))
;; Version: 0.1.0
;; This file is not part of GNU Emacs.

;; This file is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this file.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This library enables the completion of C/C++ header file names using Company.
;;
;; To initialize it, just add it to `company-backends':
;;
;; (add-to-list 'company-backends 'company-c-headers)
;;
;; When you type an #include declaration within a supported major mode (see
;; `company-c-headers-modes'), company-c-headers will search for header files
;; within predefined search paths.  company-c-headers can search "system" and
;; "user" paths, depending on the type of #include declaration you type.
;;
;; You will probably want to customize the `company-c-headers-path-user' and
;; `company-c-headers-path-system' variables for your specific needs.

;;; Code:

(require 'cl-lib)
(require 'rx)

(require 'f)
(require 'company)

(defgroup company-c-headers nil
  "Completion back-end for C/C++ header files."
  :group 'company)

(defcustom company-c-headers-path-system
  #'company-c-headers-default-path-system
  "List of paths to search for system (i.e. angle-bracket delimited) header
files.  Alternatively, a function can be supplied which returns the path list."
  :type '(choice (repeat directory)
                 function))

(defcustom company-c-headers-path-user
  '(".")
  "List of paths to search for user (i.e. double-quote delimited) header files.
Alternatively, a function can be supplied which returns the path list.  Note
that paths in `company-c-headers-path-system' are implicitly appended."
  :type '(choice (repeat directory)
                 function))

(defvar company-c-headers-include-declaration
  (rx
   line-start
   "#" (zero-or-more blank) (or "include" "import")
   (one-or-more blank)
   (submatch
    (in "<\"")
    (zero-or-more (not (in ">\"")))))
  "Prefix matching C/C++/ObjC include directives.")

(defvar company-c-headers-modes
  `((c-mode     . ,(rx ".h" line-end))
    (c++-mode   . ,(rx (or (: line-start (one-or-more (in "A-Za-z0-9_")))
                           (or ".h" ".hpp" ".hxx" ".hh"))
                       line-end))
    (objc-mode  . ,(rx ".h" line-end)))
  "Assoc list of supported major modes and associated header file names.")

(defun company-c-headers--call-if-function (path)
  "If PATH is bound to a function, return the result of calling it.
Otherwise just return the value."
  (if (functionp path) (funcall path) path))

(defun company-c-headers--candidates-for (prefix dir)
  "Return a list of candidates for PREFIX in directory DIR.
Filters on the appropriate regex for the current major mode."
  (let* ((delim (substring prefix 0 1))
         (fileprefix (substring prefix 1))
         (prefixdir (file-name-directory fileprefix))
         (subdir (and prefixdir (concat (file-name-as-directory dir) prefixdir)))
         (hdrs (cdr (assoc major-mode company-c-headers-modes)))
         candidates)

    ;; If we need to complete inside a subdirectory, use that
    (when (and subdir (file-directory-p subdir))
      (setq dir subdir)
      (setq fileprefix (file-name-nondirectory fileprefix))
      (setq delim (concat delim prefixdir)))

    ;; Using a list of completions for this directory, remove those that a) don't match the
    ;; headers regexp, and b) are not directories (except for "." and ".." which ARE removed)
    (setq candidates (cl-remove-if
                      (lambda (F) (and (not (string-match-p hdrs F))
                                       (or (cl-member (directory-file-name F) '("." "..") :test 'equal)
                                           (not (file-directory-p (concat (file-name-as-directory dir) F))))))
                      (file-name-all-completions fileprefix dir)))

    ;; We want to see candidates in alphabetical order per directory
    (setq candidates (sort candidates #'string<))

    ;; Add the delimiter and metadata
    (if (or (string= delim "\"") (string= delim "<"))
        (mapcar (lambda (C) (propertize (concat delim C) 'directory dir)) candidates)
      candidates)))

(defun company-c-headers--candidates (prefix)
  "Return candidates for PREFIX."
  (let ((p (if (equal (aref prefix 0) ?\")
               (company-c-headers--call-if-function company-c-headers-path-user)
             (company-c-headers--call-if-function company-c-headers-path-system)))
        (next (when (equal (aref prefix 0) ?\")
                (company-c-headers--call-if-function company-c-headers-path-system)))
        candidates)
    (while p
      (when (file-directory-p (car p))
        (setq candidates (append candidates (company-c-headers--candidates-for prefix (car p)))))

      (setq p (or (cdr p)
                  (let ((tmp next))
                    (setq next nil)
                    tmp))))
    (cl-remove-duplicates candidates :test 'equal)))

(defun company-c-headers--meta (candidate)
  "Return the metadata associated with CANDIDATE.  Currently just the directory."
  (get-text-property 0 'directory candidate))

(defun company-c-headers--location (candidate)
  "Return the location associated with CANDIDATE."
  (cons (concat (file-name-as-directory (get-text-property 0 'directory candidate))
                (file-name-nondirectory (substring candidate 1)))
        1))

;;;###autoload
(defun company-c-headers (command &optional arg &rest ignored)
  "Company backend for C/C++ header files."
  (interactive (list 'interactive))
  (pcase command
    (`interactive (company-begin-backend 'company-c-headers))
    (`prefix
     (when (and (assoc major-mode company-c-headers-modes)
                (looking-back company-c-headers-include-declaration (line-beginning-position)))
       (match-string-no-properties 1)))
    (`sorted t)
    (`candidates (company-c-headers--candidates arg))
    (`meta (company-c-headers--meta arg))
    (`location (company-c-headers--location arg))
    (`post-completion
     (when (looking-back company-c-headers-include-declaration (line-beginning-position))
       (let ((matched (match-string-no-properties 1)))
         (if (string= matched (file-name-as-directory matched))
             ;; This is a directory, setting `this-command' to a `self-insert-command'
             ;; tricks company to automatically trigger completion again for the
             ;; directory files.
             ;; See https://github.com/company-mode/company-mode/issues/143
             (setq this-command 'self-insert-command)
           ;; It's not a directory, add a terminating delimiter.
           ;; If pre-existing terminating delimiter already exists,
           ;; move cursor to end of line.
           (pcase (aref matched 0)
             (?\" (if (looking-at "\"") (end-of-line) (insert "\"")))
             (?<  (if (looking-at ">") (end-of-line) (insert ">"))))))))))

;;
;; (@* "Path" )
;;

(defun company-c-headers--version-check (path &rest _)
  "Check for valid PATH."
  (let ((dirname (f-filename path)))
    (ignore-errors (version-to-list dirname))))

(defun company-c-headers--guess-path (paths fn)
  "Complete a source root path with PATHS by guessing FN."
  (let ((root (nth 0 paths)) (index 0))
    (while (and root (< index (length paths)))
      (cl-incf index)
      (let ((matched (ignore-errors (f-directories root fn))))
        (setq root (when matched (concat (nth 0 matched)
                                         (nth index paths))))))
    (when root (append (list root) (f-directories root nil t)))))

;;;###autoload
(defun company-c-headers-default-path-system ()
  "Return a list system path."
  (cond
   ((memq system-type '(cygwin windows-nt ms-dos))
    (append
     (company-c-headers--guess-path
      '("C:/Program Files (x86)/Microsoft Visual Studio/" "/Community/VC/Tools/MSVC/" "/include/")
      #'company-c-headers--version-check)
     (company-c-headers--guess-path
      '("C:/Program Files/Microsoft Visual Studio/" "/Community/VC/Tools/MSVC/" "/include/")
      #'company-c-headers--version-check)
     (company-c-headers--guess-path
      '("C:/Program Files (x86)/Windows Kits/10/Include/")
      #'company-c-headers--version-check)
     (company-c-headers--guess-path
      '("C:/Program Files/Windows Kits/10/Include/")
      #'company-c-headers--version-check)))
   ((eq system-type 'darwin)
    '("/usr/lib/" "/usr/local/lib/"
      "/usr/include/c++" "/usr/local/include/c++"))
   ((eq system-type 'gnu/linux)
    '("/usr/include/" "/usr/local/include/"))))

(provide 'company-c-headers)
;;; company-c-headers.el ends here
