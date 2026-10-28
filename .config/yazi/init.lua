require("git"):setup {
	-- Order of status signs showing in the linemode
	order = 1500,
}

-- Report the current directory to the terminal (OSC 7), so new terminal
-- windows and tabs open where Yazi is.
require("term-cwd"):setup()
