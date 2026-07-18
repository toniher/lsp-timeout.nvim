# Copyright (C) 2023- Alex A. Davronov <al.neodim@gmail.com>
# See LICENSE file or comment at the top of the main file
# provided along with the source code for additional info
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.


# Install neovim binaries by version 
# usage:
# include make/neovim-install.mk
#	test-%:	$(HOME)/.neovim/%/bin/nvim | $(HOME)/.neovim/ $(HOME)/.local/share/nvim/lazy/plenary.nvim
#		VIM="$${HOME}/.neovim/$(*)/share/nvim/runtime" $(HOME)/.neovim/$(*)/bin/nvim --headless --noplugin \
#		-c "lua print('neovim version: $(*)')"
#		

ifeq ($(NEOVIM_VERSIONS),)
	$(error "neovim versions are required")
endif

# Use globally available folder for neovim
$(HOME)/.neovim/:
	mkdir -vp $@

# (GNU Make static patter is used)
# ref: https://www.gnu.org/software/make/manual/html_node/Static-Usage.html
# $HOME/.neovim/NVIM_VERSION/bin/nvim
# $HOME/.neovim/nightly/bin/nvim
# $HOME/.neovim/v0.9.2/bin/nvim
.ONESHELL:
$(patsubst %,$(HOME)/.neovim/%/bin/nvim,$(NEOVIM_VERSIONS)): $(HOME)/.neovim/%/bin/nvim: | $(HOME)/.neovim/
	echo "Downloading Nvim $(*) to \$$HOME/.neovim/$(*)/"
	mkdir -vp "$${HOME}/.neovim/$(*)"
	# Neovim's release asset was renamed from nvim-linux64.tar.gz (releases
	# <=v0.10.x) to nvim-linux-x86_64.tar.gz (v0.11+ and nightly); try the
	# new name first and fall back to the old one so this works across the
	# whole range without hardcoding a version cutover here.
	_ARCHIVE="$${HOME}/.neovim/$(*)/nvim.tar.gz"
	curl -sfL "https://github.com/neovim/neovim/releases/download/$(*)/nvim-linux-x86_64.tar.gz" -o "$${_ARCHIVE}" \
		|| curl -sfL "https://github.com/neovim/neovim/releases/download/$(*)/nvim-linux64.tar.gz" -o "$${_ARCHIVE}"
	tar --strip-components=1 -C "$${HOME}/.neovim/$(*)/" -xzf "$${_ARCHIVE}"
	rm -f "$${_ARCHIVE}"
