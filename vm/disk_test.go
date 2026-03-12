package vm

import (
	"os"
	"path/filepath"
	"testing"
)

func TestFileExists(t *testing.T) {
	t.Run("ExistingFile", func(t *testing.T) {
		f := filepath.Join(t.TempDir(), "exists.txt")
		if err := os.WriteFile(f, []byte("hello"), 0644); err != nil {
			t.Fatal(err)
		}
		if !FileExists(f) {
			t.Error("FileExists returned false for existing file")
		}
	})

	t.Run("NonExistentFile", func(t *testing.T) {
		if FileExists("/nonexistent/path/file.txt") {
			t.Error("FileExists returned true for non-existent file")
		}
	})

	t.Run("Directory", func(t *testing.T) {
		dir := t.TempDir()
		if FileExists(dir) {
			t.Error("FileExists returned true for a directory")
		}
	})
}

func TestCopyFile(t *testing.T) {
	t.Run("BasicCopy", func(t *testing.T) {
		src := filepath.Join(t.TempDir(), "src.txt")
		dst := filepath.Join(t.TempDir(), "dst.txt")

		content := []byte("kernel source tarball contents")
		if err := os.WriteFile(src, content, 0644); err != nil {
			t.Fatal(err)
		}

		if err := CopyFile(src, dst); err != nil {
			t.Fatalf("CopyFile: %v", err)
		}

		got, err := os.ReadFile(dst)
		if err != nil {
			t.Fatalf("reading dst: %v", err)
		}
		if string(got) != string(content) {
			t.Errorf("got %q, want %q", got, content)
		}
	})

	t.Run("CreatesParentDirectories", func(t *testing.T) {
		src := filepath.Join(t.TempDir(), "src.txt")
		dst := filepath.Join(t.TempDir(), "nested", "deep", "dst.txt")

		if err := os.WriteFile(src, []byte("data"), 0644); err != nil {
			t.Fatal(err)
		}

		if err := CopyFile(src, dst); err != nil {
			t.Fatalf("CopyFile: %v", err)
		}

		if !FileExists(dst) {
			t.Error("destination file was not created")
		}
	})

	t.Run("NonExistentSource", func(t *testing.T) {
		dst := filepath.Join(t.TempDir(), "dst.txt")
		if err := CopyFile("/nonexistent", dst); err == nil {
			t.Error("expected error for non-existent source")
		}
	})
}

func TestCopyDir(t *testing.T) {
	src := filepath.Join(t.TempDir(), "srcdir")
	if err := os.MkdirAll(filepath.Join(src, "sub"), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(src, "a.txt"), []byte("aaa"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(src, "sub", "b.txt"), []byte("bbb"), 0644); err != nil {
		t.Fatal(err)
	}

	dst := filepath.Join(t.TempDir(), "dstdir")
	if err := CopyDir(src, dst); err != nil {
		t.Fatalf("CopyDir: %v", err)
	}

	got, err := os.ReadFile(filepath.Join(dst, "a.txt"))
	if err != nil {
		t.Fatalf("reading a.txt: %v", err)
	}
	if string(got) != "aaa" {
		t.Errorf("a.txt: got %q", got)
	}

	got, err = os.ReadFile(filepath.Join(dst, "sub", "b.txt"))
	if err != nil {
		t.Fatalf("reading sub/b.txt: %v", err)
	}
	if string(got) != "bbb" {
		t.Errorf("sub/b.txt: got %q", got)
	}
}
