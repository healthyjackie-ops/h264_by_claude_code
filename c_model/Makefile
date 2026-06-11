CC      ?= clang
CFLAGS  ?= -O2 -Wall -Wextra -Wpedantic -Wshadow -Wconversion -Werror -std=c11 -g
LDFLAGS ?=

SRC_DIR   := src
TEST_DIR  := tests
GOLDEN_DIR:= golden
BUILD_DIR := build

CORE_SRCS := $(wildcard $(SRC_DIR)/*.c)
CORE_SRCS := $(filter-out $(SRC_DIR)/main.c,$(CORE_SRCS))
CORE_OBJS := $(patsubst $(SRC_DIR)/%.c,$(BUILD_DIR)/%.o,$(CORE_SRCS))

TEST_SRCS := $(wildcard $(TEST_DIR)/test_*.c)
TEST_BINS := $(patsubst $(TEST_DIR)/test_%.c,$(BUILD_DIR)/test_%,$(TEST_SRCS))

GOLDEN_SRC := $(GOLDEN_DIR)/golden_compare.c
GOLDEN_BIN := $(BUILD_DIR)/golden_compare

.PHONY: all test golden regress errtest clean
all: $(BUILD_DIR)/h264_decode $(GOLDEN_BIN)

VECTORS_ROOT ?= ../verification/vectors

# Per-phase golden run: `make phase05` etc. for any vectors/phase* dir.
phase%: $(GOLDEN_BIN)
	@if ls $(VECTORS_ROOT)/phase$*/*.264 >/dev/null 2>&1; then \
	  $(GOLDEN_BIN) $(VECTORS_ROOT)/phase$*/*.264; \
	else \
	  echo "[phase$*] no vectors in $(VECTORS_ROOT)/phase$* — run tools/gen_phase$*.py" >&2; \
	  exit 2; \
	fi

# Full-corpus regression: every vector in every directory except error_cases.
regress: $(GOLDEN_BIN)
	@find $(VECTORS_ROOT) -name '*.264' -not -path '*error_cases*' | sort | xargs $(GOLDEN_BIN)

ERROR_DIR := $(VECTORS_ROOT)/error_cases
errtest: $(GOLDEN_BIN) $(BUILD_DIR)/h264_decode
	@if ls $(ERROR_DIR)/*.264 >/dev/null 2>&1; then \
	  $(GOLDEN_BIN) --expect-fail $(ERROR_DIR)/*.264; \
	else \
	  echo "[errtest] no vectors in $(ERROR_DIR) — run tools/gen_error_cases.py" >&2; \
	  exit 2; \
	fi
	@if command -v leaks >/dev/null 2>&1; then \
	  for f in $(ERROR_DIR)/*.264; do \
	    leaks --atExit -- $(BUILD_DIR)/h264_decode $$f 2>&1 | grep -q " 0 leaks" \
	      || { echo "[errtest] LEAK on $$f" >&2; exit 3; }; \
	  done; \
	  echo "[errtest] leaks: clean on all error cases"; \
	else \
	  echo "[errtest] leaks tool unavailable, leak check skipped"; \
	fi

$(BUILD_DIR):
	@mkdir -p $@

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c $(wildcard $(SRC_DIR)/*.h) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -I$(SRC_DIR) -c $< -o $@

$(BUILD_DIR)/h264_decode: $(CORE_OBJS) $(BUILD_DIR)/main.o
	$(CC) $(CFLAGS) $^ -o $@ $(LDFLAGS)

$(BUILD_DIR)/main.o: $(SRC_DIR)/main.c $(wildcard $(SRC_DIR)/*.h) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -I$(SRC_DIR) -c $< -o $@

$(BUILD_DIR)/test_%: $(TEST_DIR)/test_%.c $(CORE_OBJS) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -I$(SRC_DIR) $^ -o $@ $(LDFLAGS)

$(GOLDEN_BIN): $(GOLDEN_SRC) $(CORE_OBJS) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -I$(SRC_DIR) $^ -o $@ $(LDFLAGS)

test: $(TEST_BINS)
	@set -e; for t in $(TEST_BINS); do echo "== RUN $$t =="; $$t; done; echo "ALL TESTS PASSED"

golden: $(GOLDEN_BIN)

clean:
	rm -rf $(BUILD_DIR)

# ---- sanitizer build + mutation fuzz ----
ASAN_DIR := build_asan
asan:
	@mkdir -p $(ASAN_DIR)
	$(CC) $(filter-out -O2,$(CFLAGS)) -O1 -fsanitize=address,undefined \
	  -fno-omit-frame-pointer $(SRC_DIR)/*.c -o $(ASAN_DIR)/h264_decode_asan
	@echo "[asan] built $(ASAN_DIR)/h264_decode_asan"

fuzz: asan
	python3 ../tools/fuzz_mutate.py $(ASAN_DIR)/h264_decode_asan
