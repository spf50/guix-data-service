(define-module (test-model-git-branch)
  #:use-module (srfi srfi-19)
  #:use-module (srfi srfi-64)
  #:use-module (guix-data-service database)
  #:use-module (guix-data-service model git-repository)
  #:use-module (guix-data-service model git-branch))

(test-begin "test-model-git-branch")

(with-postgresql-connection
 "test-module-git-branch"
 (lambda (conn)
   (check-test-database! conn)

   (test-assert "insert-git-branch-entry works"
     (with-postgresql-transaction
      conn
      (lambda (conn)
        (let* ((url "test-url")
               (id (git-repository-url->git-repository-id conn url)))
          (insert-git-branch-entry conn
                                   "master"
                                   "test-commit"
                                   id
                                   (current-date)))
        #t)
      #:always-rollback? #t))

   (test-assert "insert-git-branch-entry works twice"
     (with-postgresql-transaction
      conn
      (lambda (conn)
        (let* ((url "test-url")
               (id (git-repository-url->git-repository-id conn url)))
          (insert-git-branch-entry conn
                                   "master"
                                   "test-commit"
                                   id
                                   (current-date))
          (insert-git-branch-entry conn
                                   "master"
                                   "test-commit"
                                   id
                                   (current-date)))
        #t)
      #:always-rollback? #t))))

(test-end)
