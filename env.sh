# Source this file for setting up the development environment.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-${(%):-%N}}")" && pwd)"

echo $SCRIPT_DIR

if [ ! -e "${SCRIPT_DIR}/cc65/bin" ]; then
    echo "Missing cc65, please do:"
    echo ""
    echo "  $ git clone git@github.com:cc65/cc65.git"
    echo "  $ cd cc65"
    echo "  $ make"
    echo ""
    echo "To build the cc65 suite."
    echo ""
    exit 1
fi

# Add cc65 (which I cloned in this directory on my system)
# to the search path.
export PATH="$PATH:$(pwd)/cc65/bin"

# Extra lazy.
alias b='just build'
alias r='just build && just write'
