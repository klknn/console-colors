/**
* Main API file. Define the main symbols cwrite[f][ln], and color functions.
*
* Copyright: Guillaume Piolat 2014-2022.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module consolecolors;

import core.stdc.stdio: printf, FILE, fwrite, fflush, fputc;
import std.stdio : File, stdout;
import std.string: format;

private import consolecolors.term;

// Some design consideration for this library:
// - Low-hassle, it should work correctly, handle CTRL-C etc by itself.
// - We assume full D runtime, not -betterC
// - Takes over your namespace. Just provide .yellow and .on_yellow instead of a `color` function.
// - Works with C stdlib file handles, not the terminal directly, so as to mix `cwrite` and `write`.
// - 16 colors only + the "initial" one.
// - because we give colors in HTML tags, `cwrite` need to take escaped < > and & with HTML entities.
//   That's the only problem, I guess a markdown solution would also work.

public:

/// All available console colors for this library.
static immutable string[16] availableConsoleColors =
[
    "black",  "red",  "green",  "orange",  "blue",  "magenta", "cyan", "lgrey", 
    "grey", "lred", "lgreen", "yellow", "lblue", "lmagenta", "lcyan", "white"
];

pure nothrow @safe
{
    /// Terminal colors functions. Change foreground color of the text.
    /// This wraps the text around, for consumption into `cwrite` or equivalent.
    string black(const(char)[] text)
    {
        return "<black>" ~ text ~ "</black>";
    }
    ///ditto
    string red(const(char)[] text)
    {
        return "<red>" ~ text ~ "</red>";
    }
    ///ditto
    string green(const(char)[] text)
    {
        return "<green>" ~ text ~ "</green>";
    }
    ///ditto
    string orange(const(char)[] text)
    {
        return "<orange>" ~ text ~ "</orange>";
    }
    ///ditto
    string blue(const(char)[] text)
    {
        return "<blue>" ~ text ~ "</blue>";
    }
    ///ditto
    string magenta(const(char)[] text)
    {
        return "<magenta>" ~ text ~ "</magenta>";
    }
    ///ditto
    string cyan(const(char)[] text)
    {
        return "<cyan>" ~ text ~ "</cyan>";
    }
    ///ditto
    string lgrey(const(char)[] text)
    {
        return "<lgrey>" ~ text ~ "</lgrey>";
    }
    ///ditto
    string grey(const(char)[] text)
    {
        return "<grey>" ~ text ~ "</grey>";
    }
    ///ditto
    string lred(const(char)[] text)
    {
        return "<lred>" ~ text ~ "</lred>";
    }
    ///ditto
    string lgreen(const(char)[] text)
    {
        return "<lgreen>" ~ text ~ "</lgreen>";
    }
    ///ditto
    string yellow(const(char)[] text)
    {
        return "<yellow>" ~ text ~ "</yellow>";
    }
    ///ditto
    string lblue(const(char)[] text)
    {
        return "<lblue>" ~ text ~ "</lblue>";
    }
    ///ditto
    string lmagenta(const(char)[] text)
    {
        return "<lmagenta>" ~ text ~ "</lmagenta>";
    }
    ///ditto
    string lcyan(const(char)[] text)
    {
        return "<lcyan>" ~ text ~ "</lcyan>";
    }
    ///ditto
    string white(const(char)[] text)
    {
        return "<white>" ~ text ~ "</white>";
    }
}

/// Wraps text into a particular foreground color.
string color(const(char)[] text, const(char)[] color) pure @safe
{
    return format("<%s>%s</%s>", color, text, color);
}

/// Coloured `write`/`writef`/`writeln`/`writefln`.
///
/// The language that these function take as input can contain HTML tags.
/// Unknown tags have no effect and are removed.
/// Tags can't have attributes.
/// 
/// Accepted tags:
/// - <COLORNAME> such as:
///    <black>, <red>, <green>, <orange>, <blue>, <magenta>, <cyan>, <lgrey>, 
///    <grey>, <lred>, <lgreen>, <yellow>, <lblue>, <lmagenta>, <lcyan>, <white>
/// 
/// Escaping:
/// - To pass '<' as text and not a tag, use &lt;
/// - To pass '>' as text and not a tag, use &gt;
/// - To pass '&' as text not an entity, use &amp;
void cwrite(T...)(T args)
{
    import std.conv : to;

    // PERF: meh
    string s = "";
    foreach(arg; args)
        s ~= to!string(arg);

    int res = emitToTerminal(s);

    // Throw error if parsing error.
    switch(res)
    {
        case CC_ERR_OK: break;
        case CC_UNTERMINATED_TAG: throw new Exception("Unterminated <tag> in coloured text");
        case CC_UNKNOWN_TAG:      throw new Exception("Unknown <tag> in coloured text");
        case CC_MISMATCHED_TAG:   throw new Exception("Mismatched <tag> in coloured text");
        case CC_TERMINAL_ERROR:   throw new Exception("Unspecified terminal error");
        default:
            assert(false); // if you fail here, console-colors is buggy
    }
}

///ditto
void cwriteln(T...)(T args)
{
    // Most general instance
    cwrite(args, '\n');
}

///ditto
void cwritef(Char, T...)(in Char[] fmt, T args)
{
    import std.string : format;
    auto s = format(fmt, args);
    cwrite(s);
}

///ditto
void cwritefln(Char, T...)(in Char[] fmt, T args)
{
    cwritef(fmt ~ "\n", args);
}

    
// PRIVATE PARTS API START HERE
private:


enum int CC_ERR_OK = 0,           // "<blue>text</blue>"
         CC_UNTERMINATED_TAG = 1, // "<blue"
         CC_UNKNOWN_TAG = 2,      // "<pink>text</pink>"
         CC_MISMATCHED_TAG = 3,   // "<blue>text</red>"
         CC_TERMINAL_ERROR = 4;   // terminal.d error.

// Implementation of `emitToTerminal`. This is a combined lexer/parser/emitter.
// It can throw Exception in case of misformat of the input text.
int emitToTerminal( const(char)[] s) @trusted
{
    TermInterpreter* term = &g_termInterpreter;
    return term.interpret(s);  
}

private:

/// A global, shared state machine that does the terminal emulation and book-keeping.
TermInterpreter g_termInterpreter = TermInterpreter.init;

shared static this()
{
    g_termInterpreter.initialize();
}

shared static ~this()
{
    destroy(g_termInterpreter);
}

struct TermInterpreter
{
    void initialize()
    {
        if (stdoutIsTerminal)
        {
            _terminal.initialize();
            _enableTerm = true;
        }
    }

    ~this()
    {
    }

    void disableColors()
    {
        _enableTerm = false;
    }

    /// Moves the interpreter forward, eventually do actions.
    /// Return: error code.
    int interpret(const(char)[] s)
    {
        // Init tag stack.
        // State is reset between all calls to interpret, so that errors can be eaten out.

        input = s;
        inputPos = 0;

        stack(0) = Tag(TermColor.unknown, TermColor.unknown, "html");
        _tagStackIndex = 0;

        setForeground(TermColor.initial);
        setBackground(TermColor.initial);

        bool finished = false;
        bool termTextWasOutput = false;
        while(!finished)
        {
            final switch (_parserState)
            {
                case ParserState.initial:

                    Token token = getNextToken();
                    final switch(token.type)
                    {
                        case TokenType.tagOpen:
                        {
                            enterTag(token.text);
                            break;
                        }

                        case TokenType.tagClose:
                        {
                            exitTag(token.text);
                            break;
                        }

                        case TokenType.tagOpenClose:
                        {
                            enterTag(token.text);
                            exitTag(token.text);
                            break;
                        }

                        case TokenType.text:
                        {
                            stdout.write(token.text);
                            break;
                        }

                        case TokenType.endOfInput:
                            finished = true;
                            break;

                    }
                break;
            }
        }
        return 0;
    }

private:
    bool _enableTerm = false;
    Terminal _terminal;

    // Style/Tag stack
    static struct Tag
    {
        TermColor fg = TermColor.unknown;  // last applied foreground color
        TermColor bg = TermColor.unknown;  // last applied background color
        const(char)[] name; // last applied tag
    }
    enum int MAX_NESTED_TAGS = 32;

    Tag[MAX_NESTED_TAGS] _stack;
    int _tagStackIndex;

    ref Tag stack(int index) return
    {
        return _stack[index];
    }

    ref Tag stackTop() return
    {
        return _stack[_tagStackIndex];
    }

    void enterTag(const(char)[] tagName)
    {
        if (_tagStackIndex >= MAX_NESTED_TAGS)
            throw new Exception("Tag stack is full, internal error of console-colors");

        // dup top of stack, set foreground color
        stack(_tagStackIndex + 1) = stack(_tagStackIndex);
        _tagStackIndex += 1;
        stack(_tagStackIndex).name = tagName;
    
        switch(tagName)
        {
            case "black":   setForeground(TermColor.black); break;
            case "red":     setForeground(TermColor.red); break;
            case "green":   setForeground(TermColor.green); break;
            case "orange":  setForeground(TermColor.orange); break;
            case "blue":    setForeground(TermColor.blue); break;
            case "magenta": setForeground(TermColor.magenta); break;
            case "cyan":    setForeground(TermColor.cyan); break;
            case "lgrey":   setForeground(TermColor.lgrey); break;
            case "grey":    setForeground(TermColor.grey); break;
            case "lred":    setForeground(TermColor.lred); break;
            case "lgreen":  setForeground(TermColor.lgreen); break;
            case "yellow":  setForeground(TermColor.yellow); break;
            case "lblue":   setForeground(TermColor.lblue); break;
            case "lmagenta":setForeground(TermColor.lmagenta); break;
            case "lcyan":   setForeground(TermColor.lcyan); break;
            case "white":   setForeground(TermColor.white); break;
            default:
                break; // unknown tag
        }
    }

    void setForeground(TermColor fg)
    {
        assert(fg != TermColor.unknown);
        stackTop().fg = fg;
        if (_enableTerm)
            _terminal.setForegroundColor(stackTop().fg);
    }

    void setBackground(TermColor bg)
    {
        assert(bg != TermColor.unknown);
        stackTop().bg = bg;
        if (_enableTerm)
            _terminal.setBackgroundColor(stackTop().bg);
    }

    void applyStyleOnTop()
    {
        if (_enableTerm)
        {
            _terminal.setForegroundColor(stackTop().fg);
            _terminal.setBackgroundColor(stackTop().bg);
        }
    }

    /*
    void debugPrintStack()
    {
        import std.stdio;
        writeln("Stack state");
        for (int n = 0; n <= _tagStackIndex; ++n)
        {
            import std.stdio;
            writefln("tag %s   fg = %s  bg = %s",
                     _stack[_tagStackIndex].name, _stack[_tagStackIndex].fg, _stack[_tagStackIndex].bg);
        }
        writeln;
    }
    */

    void exitTag(const(char)[] tagName)
    {
        if (_tagStackIndex <= 0)
            throw new Exception("Unexpected closing tag");
        
        if (stackTop().name != tagName)
            throw new Exception("Closing tag mismatch");

        // drop one state of stack, apply old style
        _tagStackIndex -= 1;        
        applyStyleOnTop();
    }

    // <parser>

    ParserState _parserState = ParserState.initial;
    enum ParserState
    {
        initial
    }

    // </parser>

    // <lexer>

    const(char)[] input;
    int inputPos;

    LexerState _lexerState = LexerState.initial;
    enum LexerState
    {
        initial,
        insideEntity,
        insideTag,
    }

    enum TokenType
    {
        tagOpen,      // <red>
        tagClose,     // </red>
        tagOpenClose, // <red/> 
        text,
        endOfInput
    }

    static struct Token
    {
        TokenType type;

        // name of tag, or text
        const(char)[] text = null; 

        // position in input text
        int inputPos = 0;
    }

    bool hasNextChar()
    {
        return inputPos < input.length;
    }

    char peek()
    {
        return input[inputPos];
    }

    const(char)[] lastNChars(int n)
    {
        return input[inputPos - n .. inputPos];
    }

    const(char)[] charsSincePos(int pos)
    {
        return input[pos .. inputPos];
    }

    void next()
    {
        inputPos += 1;
    }

    Token getNextToken()
    {
        Token r;
        r.inputPos = inputPos;

        if (!hasNextChar())
        {
            r.type = TokenType.endOfInput;
            return r;
        }
        else if (peek() == '<')
        {
            // it is a tag
            bool closeTag = false;
            next;
            if (!hasNextChar())
                throw new Exception("Excepted tag name after <");

            if (peek() == '/')
            {
                closeTag = true;
                next;
                if (!hasNextChar())
                    throw new Exception("Excepted tag name after </");
            }

            const(char)[] tagName;
            int startOfTagName = inputPos;
            
            while(hasNextChar())
            {
                char ch = peek();
                if (ch == '/')
                {
                    tagName = charsSincePos(startOfTagName);
                    if (closeTag)
                        throw new Exception("Can't have tags like this </tagname/>");

                    next;
                    if (!hasNextChar())
                        throw new Exception("Excepted '>' in closing tag ");

                    if (peek() == '>')
                    {
                        next;

                        r.type = TokenType.tagOpenClose;
                        r.text = tagName;
                        return r;
                    }
                }
                else if (ch == '>')
                {
                    tagName = charsSincePos(startOfTagName);
                    next;
                    r.type = closeTag ? TokenType.tagClose : TokenType.tagOpen;
                    r.text = tagName;
                    return r;
                }
                else
                {
                    next;
                }
                // TODO: check chars are valid in HTML tags
            }
            throw new Exception("Unterminated tag");
        }
        else if (peek() == '&')
        {
            // it is an HTML entity
            next;
            if (!hasNextChar())
                throw new Exception("Excepted entity name after &");

            int startOfEntity = inputPos;
            while(hasNextChar())
            {
                char ch = peek();
                if (ch == ';')
                {
                    const(char)[] entityName = charsSincePos(startOfEntity);
                    switch (entityName)
                    {
                        case "lt": r.text = "<"; break;
                        case "gt": r.text = ">"; break;
                        case "amp": r.text = "&"; break;
                        default: 
                            throw new Exception("Unknown entity name");
                    }
                    next;
                    r.type = TokenType.text;
                    return r;
                }
                else if ((ch >= 'a' && ch <= 'z') || (ch >= 'a' && ch <= 'z'))
                {
                    next;
                }
                else
                    throw new Exception("Illegal character in entity name, you probably mean &lt; or &gt; or &amp;");                
            }
            throw new Exception("Unfinished entity name, you probably mean &lt; or &gt; or &amp;");
        }
        else 
        {
            int startOfText = inputPos;
            while(hasNextChar())
            {
                char ch = peek();
                if (ch == '>')
                    throw new Exception("Illegal character >, use &gt; instead if intended");
                if (ch == '<') 
                    break;
                if (ch == '&') 
                    break;
                next;
            }
            assert(inputPos != startOfText);
            r.type = TokenType.text;
            r.text = charsSincePos(startOfText);
            return r;
        }
    }
}
