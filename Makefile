# DOUGLAS Makefile — 빌드/테스트/린트 통합 진입점

.PHONY: build test coverage lint lint-fix dist install-hooks clean help

SWIFT := swift
SWIFTLINT := swiftlint

## 릴리즈 빌드
build:
	$(SWIFT) build -c release

## 전체 테스트 실행
test:
	$(SWIFT) test

## 커버리지 포함 테스트 + 리포트 출력
coverage:
	$(SWIFT) test --enable-code-coverage
	@TESTBIN=$$(find .build -path "*/DOUGLASPackageTests.xctest/Contents/MacOS/DOUGLASPackageTests" 2>/dev/null | head -1); \
	PROFDATA=$$(find .build -name "default.profdata" 2>/dev/null | head -1); \
	if [ -n "$$PROFDATA" ] && [ -n "$$TESTBIN" ]; then \
		xcrun llvm-cov report "$$TESTBIN" \
			-instr-profile "$$PROFDATA" \
			--ignore-filename-regex="Tests/" \
			--ignore-filename-regex=".build/"; \
	else \
		echo "커버리지 데이터를 찾을 수 없습니다."; \
	fi

## SwiftLint 실행
lint:
	@if command -v $(SWIFTLINT) >/dev/null 2>&1; then \
		$(SWIFTLINT) lint --config .swiftlint.yml; \
	else \
		echo "SwiftLint 미설치. brew install swiftlint 실행 후 재시도"; \
	fi

## SwiftLint 자동 수정
lint-fix:
	@if command -v $(SWIFTLINT) >/dev/null 2>&1; then \
		$(SWIFTLINT) --fix --config .swiftlint.yml; \
	else \
		echo "SwiftLint 미설치"; \
	fi

## DMG 패키징
dist:
	bash scripts/build-app.sh

## pre-commit + commit-msg 훅 설치
install-hooks:
	@cp scripts/pre-commit .git/hooks/pre-commit
	@chmod +x .git/hooks/pre-commit
	@cp scripts/commit-msg .git/hooks/commit-msg
	@chmod +x .git/hooks/commit-msg
	@echo "훅 설치 완료: pre-commit, commit-msg"

## 빌드 산출물 정리
clean:
	rm -rf .build dist

## 도움말
help:
	@echo "사용 가능한 타겟:"
	@echo "  make build         릴리즈 빌드"
	@echo "  make test          전체 테스트 실행"
	@echo "  make coverage      커버리지 포함 테스트 + 리포트"
	@echo "  make lint          SwiftLint 실행"
	@echo "  make lint-fix      SwiftLint 자동 수정"
	@echo "  make dist          DMG 패키징"
	@echo "  make install-hooks pre-commit/commit-msg 훅 설치"
	@echo "  make clean         빌드 산출물 정리"
