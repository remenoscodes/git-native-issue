prefix = /usr/local
bindir = $(prefix)/bin
mandir = $(prefix)/share/man/man1

SCRIPTS = $(wildcard bin/git-issue*)
MANPAGES = $(wildcard doc/git-issue*.1)
VERSION = $(shell sed -n 's/^VERSION="\(.*\)"/\1/p' bin/git-issue)

all:
	@echo "git-issue $(VERSION)"
	@echo "  make install          Install to $(bindir)"
	@echo "  make install prefix=~ Install to ~/bin"
	@echo "  make uninstall        Remove from $(bindir)"
	@echo "  make install-doc      Install man pages to $(mandir)"
	@echo "  make uninstall-doc    Remove man pages from $(mandir)"
	@echo "  make test             Run all tests"

install:
	install -d $(DESTDIR)$(bindir)
	install -m 755 $(SCRIPTS) $(DESTDIR)$(bindir)/

uninstall:
	rm -f $(DESTDIR)$(bindir)/git-issue $(DESTDIR)$(bindir)/git-issue-*

install-doc:
	install -d $(DESTDIR)$(mandir)
	install -m 644 $(MANPAGES) $(DESTDIR)$(mandir)/

uninstall-doc:
	cd $(DESTDIR)$(mandir) && rm -f git-issue.1 git-issue-*.1

test:
	@sh t/test-issue.sh
	@sh t/test-labels-validation.sh
	@sh t/test-concurrency.sh
	@sh t/test-assignee-validation.sh
	@sh t/test-bridge.sh
	@sh t/test-merge.sh
	@sh t/test-qol.sh
	@sh t/test-comment-sync.sh

clean:
	rm -rf t/tmp-*

.PHONY: all install uninstall install-doc uninstall-doc test clean
