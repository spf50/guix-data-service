;;; Guix Data Service -- Information about Guix over time
;;; Copyright © 2019 Christopher Baines <mail@cbaines.net>
;;;
;;; This program is free software: you can redistribute it and/or
;;; modify it under the terms of the GNU Affero General Public License
;;; as published by the Free Software Foundation, either version 3 of
;;; the License, or (at your option) any later version.
;;;
;;; This program is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;;; Affero General Public License for more details.
;;;
;;; You should have received a copy of the GNU Affero General Public
;;; License along with this program.  If not, see
;;; <http://www.gnu.org/licenses/>.

(define-module (guix-data-service branch-updated-emails)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-11)
  #:use-module (srfi srfi-19)
  #:use-module (email email)
  #:use-module (guix-data-service model git-repository)
  #:use-module (guix-data-service model git-branch)
  #:use-module (guix-data-service jobs load-new-guix-revision)
  #:export (enqueue-job-for-email))

(define commit-all-zeros
  "0000000000000000000000000000000000000000")

(define (enqueue-job-for-email conn email)
  (let* ((headers       (email-headers email))
         (date          (assq-ref headers 'date))
         (x-git-repo    (assq-ref headers 'x-git-repo))
         (x-git-reftype (assq-ref headers 'x-git-reftype))
         (x-git-refname (assq-ref headers 'x-git-refname))
         (x-git-newrev  (assq-ref headers 'x-git-newrev)))
    (when (and (and (string? x-git-reftype)
                    (string=? x-git-reftype "branch"))
               (string? x-git-newrev))

      (let ((branch-name
             (string-drop x-git-refname 11))
            (git-repository-id
             (git-repository-x-git-repo-header->git-repository-id
              conn
              x-git-repo)))

        (when git-repository-id
          (let-values
              (((included-branches excluded-branches)
                (select-includes-and-excluded-branches-for-git-repository
                 conn
                 git-repository-id)))
            (let ((excluded-branch?
                   (member branch-name excluded-branches string=?))
                  (included-branch?
                   (member branch-name included-branches string=?)))
              (when (and (not excluded-branch?)
                         (or (null? included-branches)
                             included-branch?))
                (insert-git-branch-entry conn
                                         branch-name
                                         (if (string=? commit-all-zeros
                                                       x-git-newrev)
                                             ""
                                             x-git-newrev)
                                         git-repository-id
                                         date)

                (unless (string=? commit-all-zeros x-git-newrev)
                  (enqueue-load-new-guix-revision-job
                   conn
                   git-repository-id
                   x-git-newrev
                   (string-append x-git-repo " "
                                  x-git-refname " updated")))))))))))
