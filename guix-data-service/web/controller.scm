;;; Guix Data Service -- Information about Guix over time
;;; Copyright © 2016, 2017, 2018, 2019 Ricardo Wurmus <rekado@elephly.net>
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

(define-module (guix-data-service web controller)
  #:use-module (ice-9 match)
  #:use-module (ice-9 vlist)
  #:use-module (ice-9 pretty-print)
  #:use-module (ice-9 textual-ports)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-11)
  #:use-module (srfi srfi-26)
  #:use-module (web request)
  #:use-module (web uri)
  #:use-module (texinfo)
  #:use-module (texinfo html)
  #:use-module (squee)
  #:use-module (json)
  #:use-module (guix-data-service config)
  #:use-module (guix-data-service comparison)
  #:use-module (guix-data-service database)
  #:use-module (guix-data-service model git-branch)
  #:use-module (guix-data-service model git-repository)
  #:use-module (guix-data-service model guix-revision)
  #:use-module (guix-data-service model package)
  #:use-module (guix-data-service model package-derivation)
  #:use-module (guix-data-service model package-metadata)
  #:use-module (guix-data-service model derivation)
  #:use-module (guix-data-service model build-status)
  #:use-module (guix-data-service model build)
  #:use-module (guix-data-service model lint-checker)
  #:use-module (guix-data-service model lint-warning)
  #:use-module (guix-data-service model utils)
  #:use-module (guix-data-service jobs load-new-guix-revision)
  #:use-module (guix-data-service web render)
  #:use-module (guix-data-service web sxml)
  #:use-module (guix-data-service web query-parameters)
  #:use-module (guix-data-service web util)
  #:use-module (guix-data-service web revision controller)
  #:use-module (guix-data-service web jobs controller)
  #:use-module (guix-data-service web view html)
  #:use-module (guix-data-service web compare controller)
  #:use-module (guix-data-service web revision controller)
  #:use-module (guix-data-service web repository controller)
  #:export (controller))

(define cache-control-default-max-age
  (* 60 60 24)) ; One day

(define http-headers-for-unchanging-content
  `((cache-control
     . (public
        (max-age . ,cache-control-default-max-age)))))

(define-syntax-rule (-> target functions ...)
  (fold (lambda (f val) (and=> val f))
        target
        (list functions ...)))

(define (render-with-error-handling page message)
  (apply render-html (page))
  ;; (catch #t
  ;;   (lambda ()
  ;;     (receive (sxml headers)
  ;;         (pretty-print (page))
  ;;       (render-html sxml headers)))
  ;;   (lambda (key . args)
  ;;     (format #t "ERROR: ~a ~a\n"
  ;;             key args)
  ;;     (render-html (error-page message))))
  )

(define (assoc-ref-multiple alist key)
  (filter-map
   (match-lambda
     ((k . value)
      (and (string=? k key)
           value)))
   alist))

(define (render-derivation conn derivation-file-name)
  (let ((derivation (select-derivation-by-file-name conn
                                                    derivation-file-name)))
    (if derivation
        (let ((derivation-inputs (select-derivation-inputs-by-derivation-id
                                  conn
                                  (first derivation)))
              (derivation-outputs (select-derivation-outputs-by-derivation-id
                                   conn
                                   (first derivation)))
              (builds (select-builds-with-context-by-derivation-id
                       conn
                       (first derivation))))
          (render-html
           #:sxml (view-derivation derivation
                                   derivation-inputs
                                   derivation-outputs
                                   builds)
           #:extra-headers http-headers-for-unchanging-content))

        (render-html
         #:sxml (general-not-found
                 "Derivation not found"
                 "No derivation found with this file name.")
         #:code 404))))

(define (render-formatted-derivation conn derivation-file-name)
  (let ((derivation (select-derivation-by-file-name conn
                                                    derivation-file-name)))
    (if derivation
        (let ((derivation-inputs (select-derivation-inputs-by-derivation-id
                                  conn
                                  (first derivation)))
              (derivation-outputs (select-derivation-outputs-by-derivation-id
                                   conn
                                   (first derivation)))
              (derivation-sources (select-derivation-sources-by-derivation-id
                                   conn
                                   (first derivation))))
          (render-html
           #:sxml (view-formatted-derivation derivation
                                             derivation-inputs
                                             derivation-outputs
                                             derivation-sources)
           #:extra-headers http-headers-for-unchanging-content))

        (render-html
         #:sxml (general-not-found
                 "Derivation not found"
                 "No derivation found with this file name.")
         #:code 404))))

(define (render-store-item conn filename)
  (let ((derivation (select-derivation-by-output-filename conn filename)))
    (match derivation
      (()
       (render-html
        #:sxml (general-not-found
                "Store item not found"
                "No derivation found producing this output")
        #:code 404))
      (derivations
       (render-html
        #:sxml (view-store-item filename
                                derivations
                                (map (lambda (derivation)
                                       (match derivation
                                         ((file-name output-id rest ...)
                                          (select-derivations-using-output
                                           conn output-id))))
                                     derivations))
        #:extra-headers http-headers-for-unchanging-content)))))

(define handle-static-assets
  (if assets-dir-in-store?
      (static-asset-from-store-renderer)
      render-static-asset))

(define (controller request method-and-path-components mime-types body)
  (match method-and-path-components
    (('GET "assets" rest ...)
     (or (handle-static-assets (string-join rest "/")
                               (request-headers request))
         (not-found (request-uri request))))
    (('GET "healthcheck")
     (let ((database-status
            (catch
              #t
              (lambda ()
                (with-postgresql-connection
                 "web healthcheck"
                 (lambda (conn)
                   (number?
                    (string->number
                     (first
                      (count-guix-revisions conn)))))))
              (lambda (key . args)
                #f))))
       (render-json
        `((status . ,(if database-status
                         "ok"
                         "not ok")))
        #:code (if (eq? database-status
                        #t)
                   200
                   500))))
    (('GET "README")
     (let ((filename (string-append (%config 'doc-dir) "/README.html")))
       (if (file-exists? filename)
           (render-html
            #:sxml (readme (call-with-input-file filename
                             get-string-all)))
           (render-html
            #:sxml (general-not-found
                    "README not found"
                    "The README.html file does not exist")
            #:code 404))))
    (_
     (with-postgresql-connection
      "web"
      (lambda (conn)
        (controller-with-database-connection request
                                             method-and-path-components
                                             mime-types
                                             body
                                             conn))))))

(define (controller-with-database-connection request
                                             method-and-path-components
                                             mime-types
                                             body
                                             conn)
  (define path
    (uri-path (request-uri request)))

  (define (delegate-to f)
    (or (f request
           method-and-path-components
           mime-types
           body
           conn)
        (not-found (request-uri request))))

  (match method-and-path-components
    (('GET)
     (render-html
      #:sxml (index
              (map
               (lambda (git-repository-details)
                 (cons
                  git-repository-details
                  (all-branches-with-most-recent-commit
                   conn (first git-repository-details))))
               (all-git-repositories conn)))))
    (('GET "builds")
     (render-html
      #:sxml (view-builds (select-build-stats conn)
                          (select-builds-with-context conn))))
    (('GET "statistics")
     (render-html
      #:sxml (view-statistics (count-guix-revisions conn)
                              (count-derivations conn))))
    (('GET "revision" args ...)
     (delegate-to revision-controller))
    (('GET "repository" _ ...)
     (delegate-to repository-controller))
    (('GET "gnu" "store" filename)
     ;; These routes are a little special, as the extensions aren't used for
     ;; content negotiation, so just use the path from the request
     (let ((path (uri-path (request-uri request))))
       (if (string-suffix? ".drv" path)
           (render-derivation conn path)
           (render-store-item conn path))))
    (('GET "gnu" "store" filename "formatted")
     (if (string-suffix? ".drv" filename)
         (render-formatted-derivation conn
                                      (string-append "/gnu/store/" filename))
         (not-found (request-uri request))))
    (('GET "compare" _ ...)             (delegate-to compare-controller))
    (('GET "compare-by-datetime" _ ...) (delegate-to compare-controller))
    (('GET "jobs")         (delegate-to jobs-controller))
    (('GET "jobs" "queue") (delegate-to jobs-controller))
    (('GET "job" job-id)   (delegate-to jobs-controller))
    (('GET path ...)
     (not-found (request-uri request)))))
