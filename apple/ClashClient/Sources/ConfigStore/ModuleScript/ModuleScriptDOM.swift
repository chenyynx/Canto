#if os(iOS) || os(macOS)
import JavaScriptCore

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 

enum ModuleScriptDOM {
     
    static func isWanted(by source: String) -> Bool { source.contains("DOMParser") }

     
     
     
     
     
     
     
     
    @discardableResult
    static func install(into context: JSContext, maximumSourceBytes: Int? = nil) -> Bool {
        let handler = context.exceptionHandler
        var threw = false
        context.exceptionHandler = { _, _ in threw = true }
        if let installer = context.evaluateScript(source), !threw, let global = context.globalObject {
            let limit: Any = maximumSourceBytes.map { NSNumber(value: $0) } ?? NSNull()
            installer.call(withArguments: [global, limit])
        }
        context.exceptionHandler = handler
        return !threw
    }

     
    private static let source = ##"""
// Evaluated, this is the installer: called with the global object and the
// page's cap in UTF-8 bytes (null for none).
(function (global, sourceLimit) {
'use strict';

// ---- Errors -------------------------------------------------------------

var CODES = { IndexSizeError: 1, HierarchyRequestError: 3, WrongDocumentError: 4, InvalidCharacterError: 5,
              NotFoundError: 8, NotSupportedError: 9, InvalidStateError: 11, SyntaxError: 12, NamespaceError: 14 };

function domError(name, message) {
  var error = new Error(message);
  Object.defineProperty(error, 'name', { value: name, writable: true, configurable: true });
  Object.defineProperty(error, 'code', { value: CODES[name] || 0, writable: true, configurable: true });
  return error;
}

function hidden(object, name, value) {
  Object.defineProperty(object, name, { value: value, writable: true, enumerable: false, configurable: true });
}

// ---- Character references -----------------------------------------------
// The HTML Standard's named character references (WHATWG, CC BY 4.0), one
// `name:codepoint[.codepoint]` a comma, and the names that may come without
// their semicolon. A name is looked up in the text itself, and what was
// found kept: no map of all 2,125 is ever made.

var ENTITY_DATA = ',AElig:c6,AMP:26,Aacute:c1,Abreve:102,Acirc:c2,Acy:410,Afr:1d504,Agrave:c0,Alpha:391,Amacr:100,And:2a53,Aogon:104,Aopf:1d538,ApplyFunction:2061,Aring:c5,Ascr:1d49c,Assign:2254,Atilde:c3,Auml:c4,Backslash:2216,Barv:2ae7,Barwed:2306,Bcy:411,Because:2235,Bernoullis:212c,Beta:392,Bfr:1d505,Bopf:1d539,Breve:2d8,Bscr:212c,Bumpeq:224e,CHcy:427,COPY:a9,Cacute:106,Cap:22d2,CapitalDifferentialD:2145,Cayleys:212d,Ccaron:10c,Ccedil:c7,Ccirc:108,Cconint:2230,Cdot:10a,Cedilla:b8,CenterDot:b7,Cfr:212d,Chi:3a7,CircleDot:2299,CircleMinus:2296,CirclePlus:2295,CircleTimes:2297,ClockwiseContourIntegral:2232,CloseCurlyDoubleQuote:201d,CloseCurlyQuote:2019,Colon:2237,Colone:2a74,Congruent:2261,Conint:222f,ContourIntegral:222e,Copf:2102,Coproduct:2210,CounterClockwiseContourIntegral:2233,Cross:2a2f,Cscr:1d49e,Cup:22d3,CupCap:224d,DD:2145,DDotrahd:2911,DJcy:402,DScy:405,DZcy:40f,Dagger:2021,Darr:21a1,Dashv:2ae4,Dcaron:10e,Dcy:414,Del:2207,Delta:394,Dfr:1d507,DiacriticalAcute:b4,DiacriticalDot:2d9,DiacriticalDoubleAcute:2dd,DiacriticalGrave:60,DiacriticalTilde:2dc,Diamond:22c4,DifferentialD:2146,Dopf:1d53b,Dot:a8,DotDot:20dc,DotEqual:2250,DoubleContourIntegral:222f,DoubleDot:a8,DoubleDownArrow:21d3,DoubleLeftArrow:21d0,DoubleLeftRightArrow:21d4,DoubleLeftTee:2ae4,DoubleLongLeftArrow:27f8,DoubleLongLeftRightArrow:27fa,DoubleLongRightArrow:27f9,DoubleRightArrow:21d2,DoubleRightTee:22a8,DoubleUpArrow:21d1,DoubleUpDownArrow:21d5,DoubleVerticalBar:2225,DownArrow:2193,DownArrowBar:2913,DownArrowUpArrow:21f5,DownBreve:311,DownLeftRightVector:2950,DownLeftTeeVector:295e,DownLeftVector:21bd,DownLeftVectorBar:2956,DownRightTeeVector:295f,DownRightVector:21c1,DownRightVectorBar:2957,DownTee:22a4,DownTeeArrow:21a7,Downarrow:21d3,Dscr:1d49f,Dstrok:110,ENG:14a,ETH:d0,Eacute:c9,Ecaron:11a,Ecirc:ca,Ecy:42d,Edot:116,Efr:1d508,Egrave:c8,Element:2208,Emacr:112,EmptySmallSquare:25fb,EmptyVerySmallSquare:25ab,Eogon:118,Eopf:1d53c,Epsilon:395,Equal:2a75,EqualTilde:2242,Equilibrium:21cc,Escr:2130,Esim:2a73,Eta:397,Euml:cb,Exists:2203,ExponentialE:2147,Fcy:424,Ffr:1d509,FilledSmallSquare:25fc,FilledVerySmallSquare:25aa,Fopf:1d53d,ForAll:2200,Fouriertrf:2131,Fscr:2131,GJcy:403,GT:3e,Gamma:393,Gammad:3dc,Gbreve:11e,Gcedil:122,Gcirc:11c,Gcy:413,Gdot:120,Gfr:1d50a,Gg:22d9,Gopf:1d53e,GreaterEqual:2265,GreaterEqualLess:22db,GreaterFullEqual:2267,GreaterGreater:2aa2,GreaterLess:2277,GreaterSlantEqual:2a7e,GreaterTilde:2273,Gscr:1d4a2,Gt:226b,HARDcy:42a,Hacek:2c7,Hat:5e,Hcirc:124,Hfr:210c,HilbertSpace:210b,Hopf:210d,HorizontalLine:2500,Hscr:210b,Hstrok:126,HumpDownHump:224e,HumpEqual:224f,IEcy:415,IJlig:132,IOcy:401,Iacute:cd,Icirc:ce,Icy:418,Idot:130,Ifr:2111,Igrave:cc,Im:2111,Imacr:12a,ImaginaryI:2148,Implies:21d2,Int:222c,Integral:222b,Intersection:22c2,InvisibleComma:2063,InvisibleTimes:2062,Iogon:12e,Iopf:1d540,Iota:399,Iscr:2110,Itilde:128,Iukcy:406,Iuml:cf,Jcirc:134,Jcy:419,Jfr:1d50d,Jopf:1d541,Jscr:1d4a5,Jsercy:408,Jukcy:404,KHcy:425,KJcy:40c,Kappa:39a,Kcedil:136,Kcy:41a,Kfr:1d50e,Kopf:1d542,Kscr:1d4a6,LJcy:409,LT:3c,Lacute:139,Lambda:39b,Lang:27ea,Laplacetrf:2112,Larr:219e,Lcaron:13d,Lcedil:13b,Lcy:41b,LeftAngleBracket:27e8,LeftArrow:2190,LeftArrowBar:21e4,LeftArrowRightArrow:21c6,LeftCeiling:2308,LeftDoubleBracket:27e6,LeftDownTeeVector:2961,LeftDownVector:21c3,LeftDownVectorBar:2959,LeftFloor:230a,LeftRightArrow:2194,LeftRightVector:294e,LeftTee:22a3,LeftTeeArrow:21a4,LeftTeeVector:295a,LeftTriangle:22b2,LeftTriangleBar:29cf,LeftTriangleEqual:22b4,LeftUpDownVector:2951,LeftUpTeeVector:2960,LeftUpVector:21bf,LeftUpVectorBar:2958,LeftVector:21bc,LeftVectorBar:2952,Leftarrow:21d0,Leftrightarrow:21d4,LessEqualGreater:22da,LessFullEqual:2266,LessGreater:2276,LessLess:2aa1,LessSlantEqual:2a7d,LessTilde:2272,Lfr:1d50f,Ll:22d8,Lleftarrow:21da,Lmidot:13f,LongLeftArrow:27f5,LongLeftRightArrow:27f7,LongRightArrow:27f6,Longleftarrow:27f8,Longleftrightarrow:27fa,Longrightarrow:27f9,Lopf:1d543,LowerLeftArrow:2199,LowerRightArrow:2198,Lscr:2112,Lsh:21b0,Lstrok:141,Lt:226a,Map:2905,Mcy:41c,MediumSpace:205f,Mellintrf:2133,Mfr:1d510,MinusPlus:2213,Mopf:1d544,Mscr:2133,Mu:39c,NJcy:40a,Nacute:143,Ncaron:147,Ncedil:145,Ncy:41d,NegativeMediumSpace:200b,NegativeThickSpace:200b,NegativeThinSpace:200b,NegativeVeryThinSpace:200b,NestedGreaterGreater:226b,NestedLessLess:226a,NewLine:a,Nfr:1d511,NoBreak:2060,NonBreakingSpace:a0,Nopf:2115,Not:2aec,NotCongruent:2262,NotCupCap:226d,NotDoubleVerticalBar:2226,NotElement:2209,NotEqual:2260,NotEqualTilde:2242.338,NotExists:2204,NotGreater:226f,NotGreaterEqual:2271,NotGreaterFullEqual:2267.338,NotGreaterGreater:226b.338,NotGreaterLess:2279,NotGreaterSlantEqual:2a7e.338,NotGreaterTilde:2275,NotHumpDownHump:224e.338,NotHumpEqual:224f.338,NotLeftTriangle:22ea,NotLeftTriangleBar:29cf.338,NotLeftTriangleEqual:22ec,NotLess:226e,NotLessEqual:2270,NotLessGreater:2278,NotLessLess:226a.338,NotLessSlantEqual:2a7d.338,NotLessTilde:2274,NotNestedGreaterGreater:2aa2.338,NotNestedLessLess:2aa1.338,NotPrecedes:2280,NotPrecedesEqual:2aaf.338,NotPrecedesSlantEqual:22e0,NotReverseElement:220c,NotRightTriangle:22eb,NotRightTriangleBar:29d0.338,NotRightTriangleEqual:22ed,NotSquareSubset:228f.338,NotSquareSubsetEqual:22e2,NotSquareSuperset:2290.338,NotSquareSupersetEqual:22e3,NotSubset:2282.20d2,NotSubsetEqual:2288,NotSucceeds:2281,NotSucceedsEqual:2ab0.338,NotSucceedsSlantEqual:22e1,NotSucceedsTilde:227f.338,NotSuperset:2283.20d2,NotSupersetEqual:2289,NotTilde:2241,NotTildeEqual:2244,NotTildeFullEqual:2247,NotTildeTilde:2249,NotVerticalBar:2224,Nscr:1d4a9,Ntilde:d1,Nu:39d,OElig:152,Oacute:d3,Ocirc:d4,Ocy:41e,Odblac:150,Ofr:1d512,Ograve:d2,Omacr:14c,Omega:3a9,Omicron:39f,Oopf:1d546,OpenCurlyDoubleQuote:201c,OpenCurlyQuote:2018,Or:2a54,Oscr:1d4aa,Oslash:d8,Otilde:d5,Otimes:2a37,Ouml:d6,OverBar:203e,OverBrace:23de,OverBracket:23b4,OverParenthesis:23dc,PartialD:2202,Pcy:41f,Pfr:1d513,Phi:3a6,Pi:3a0,PlusMinus:b1,Poincareplane:210c,Popf:2119,Pr:2abb,Precedes:227a,PrecedesEqual:2aaf,PrecedesSlantEqual:227c,PrecedesTilde:227e,Prime:2033,Product:220f,Proportion:2237,Proportional:221d,Pscr:1d4ab,Psi:3a8,QUOT:22,Qfr:1d514,Qopf:211a,Qscr:1d4ac,RBarr:2910,REG:ae,Racute:154,Rang:27eb,Rarr:21a0,Rarrtl:2916,Rcaron:158,Rcedil:156,Rcy:420,Re:211c,ReverseElement:220b,ReverseEquilibrium:21cb,ReverseUpEquilibrium:296f,Rfr:211c,Rho:3a1,RightAngleBracket:27e9,RightArrow:2192,RightArrowBar:21e5,RightArrowLeftArrow:21c4,RightCeiling:2309,RightDoubleBracket:27e7,RightDownTeeVector:295d,RightDownVector:21c2,RightDownVectorBar:2955,RightFloor:230b,RightTee:22a2,RightTeeArrow:21a6,RightTeeVector:295b,RightTriangle:22b3,RightTriangleBar:29d0,RightTriangleEqual:22b5,RightUpDownVector:294f,RightUpTeeVector:295c,RightUpVector:21be,RightUpVectorBar:2954,RightVector:21c0,RightVectorBar:2953,Rightarrow:21d2,Ropf:211d,RoundImplies:2970,Rrightarrow:21db,Rscr:211b,Rsh:21b1,RuleDelayed:29f4,SHCHcy:429,SHcy:428,SOFTcy:42c,Sacute:15a,Sc:2abc,Scaron:160,Scedil:15e,Scirc:15c,Scy:421,Sfr:1d516,ShortDownArrow:2193,ShortLeftArrow:2190,ShortRightArrow:2192,ShortUpArrow:2191,Sigma:3a3,SmallCircle:2218,Sopf:1d54a,Sqrt:221a,Square:25a1,SquareIntersection:2293,SquareSubset:228f,SquareSubsetEqual:2291,SquareSuperset:2290,SquareSupersetEqual:2292,SquareUnion:2294,Sscr:1d4ae,Star:22c6,Sub:22d0,Subset:22d0,SubsetEqual:2286,Succeeds:227b,SucceedsEqual:2ab0,SucceedsSlantEqual:227d,SucceedsTilde:227f,SuchThat:220b,Sum:2211,Sup:22d1,Superset:2283,SupersetEqual:2287,Supset:22d1,THORN:de,TRADE:2122,TSHcy:40b,TScy:426,Tab:9,Tau:3a4,Tcaron:164,Tcedil:162,Tcy:422,Tfr:1d517,Therefore:2234,Theta:398,ThickSpace:205f.200a,ThinSpace:2009,Tilde:223c,TildeEqual:2243,TildeFullEqual:2245,TildeTilde:2248,Topf:1d54b,TripleDot:20db,Tscr:1d4af,Tstrok:166,Uacute:da,Uarr:219f,Uarrocir:2949,Ubrcy:40e,Ubreve:16c,Ucirc:db,Ucy:423,Udblac:170,Ufr:1d518,Ugrave:d9,Umacr:16a,UnderBar:5f,UnderBrace:23df,UnderBracket:23b5,UnderParenthesis:23dd,Union:22c3,UnionPlus:228e,Uogon:172,Uopf:1d54c,UpArrow:2191,UpArrowBar:2912,UpArrowDownArrow:21c5,UpDownArrow:2195,UpEquilibrium:296e,UpTee:22a5,UpTeeArrow:21a5,Uparrow:21d1,Updownarrow:21d5,UpperLeftArrow:2196,UpperRightArrow:2197,Upsi:3d2,Upsilon:3a5,Uring:16e,Uscr:1d4b0,Utilde:168,Uuml:dc,VDash:22ab,Vbar:2aeb,Vcy:412,Vdash:22a9,Vdashl:2ae6,Vee:22c1,Verbar:2016,Vert:2016,VerticalBar:2223,VerticalLine:7c,VerticalSeparator:2758,VerticalTilde:2240,VeryThinSpace:200a,Vfr:1d519,Vopf:1d54d,Vscr:1d4b1,Vvdash:22aa,Wcirc:174,Wedge:22c0,Wfr:1d51a,Wopf:1d54e,Wscr:1d4b2,Xfr:1d51b,Xi:39e,Xopf:1d54f,Xscr:1d4b3,YAcy:42f,YIcy:407,YUcy:42e,Yacute:dd,Ycirc:176,Ycy:42b,Yfr:1d51c,Yopf:1d550,Yscr:1d4b4,Yuml:178,ZHcy:416,Zacute:179,Zcaron:17d,Zcy:417,Zdot:17b,ZeroWidthSpace:200b,Zeta:396,Zfr:2128,Zopf:2124,Zscr:1d4b5,aacute:e1,abreve:103,ac:223e,acE:223e.333,acd:223f,acirc:e2,acute:b4,acy:430,aelig:e6,af:2061,afr:1d51e,agrave:e0,alefsym:2135,aleph:2135,alpha:3b1,amacr:101,amalg:2a3f,amp:26,and:2227,andand:2a55,andd:2a5c,andslope:2a58,andv:2a5a,ang:2220,ange:29a4,angle:2220,angmsd:2221,angmsdaa:29a8,angmsdab:29a9,angmsdac:29aa,angmsdad:29ab,angmsdae:29ac,angmsdaf:29ad,angmsdag:29ae,angmsdah:29af,angrt:221f,angrtvb:22be,angrtvbd:299d,angsph:2222,angst:c5,angzarr:237c,aogon:105,aopf:1d552,ap:2248,apE:2a70,apacir:2a6f,ape:224a,apid:224b,apos:27,approx:2248,approxeq:224a,aring:e5,ascr:1d4b6,ast:2a,asymp:2248,asympeq:224d,atilde:e3,auml:e4,awconint:2233,awint:2a11,bNot:2aed,backcong:224c,backepsilon:3f6,backprime:2035,backsim:223d,backsimeq:22cd,barvee:22bd,barwed:2305,barwedge:2305,bbrk:23b5,bbrktbrk:23b6,bcong:224c,bcy:431,bdquo:201e,becaus:2235,because:2235,bemptyv:29b0,bepsi:3f6,bernou:212c,beta:3b2,beth:2136,between:226c,bfr:1d51f,bigcap:22c2,bigcirc:25ef,bigcup:22c3,bigodot:2a00,bigoplus:2a01,bigotimes:2a02,bigsqcup:2a06,bigstar:2605,bigtriangledown:25bd,bigtriangleup:25b3,biguplus:2a04,bigvee:22c1,bigwedge:22c0,bkarow:290d,blacklozenge:29eb,blacksquare:25aa,blacktriangle:25b4,blacktriangledown:25be,blacktriangleleft:25c2,blacktriangleright:25b8,blank:2423,blk12:2592,blk14:2591,blk34:2593,block:2588,bne:3d.20e5,bnequiv:2261.20e5,bnot:2310,bopf:1d553,bot:22a5,bottom:22a5,bowtie:22c8,boxDL:2557,boxDR:2554,boxDl:2556,boxDr:2553,boxH:2550,boxHD:2566,boxHU:2569,boxHd:2564,boxHu:2567,boxUL:255d,boxUR:255a,boxUl:255c,boxUr:2559,boxV:2551,boxVH:256c,boxVL:2563,boxVR:2560,boxVh:256b,boxVl:2562,boxVr:255f,boxbox:29c9,boxdL:2555,boxdR:2552,boxdl:2510,boxdr:250c,boxh:2500,boxhD:2565,boxhU:2568,boxhd:252c,boxhu:2534,boxminus:229f,boxplus:229e,boxtimes:22a0,boxuL:255b,boxuR:2558,boxul:2518,boxur:2514,boxv:2502,boxvH:256a,boxvL:2561,boxvR:255e,boxvh:253c,boxvl:2524,boxvr:251c,bprime:2035,breve:2d8,brvbar:a6,bscr:1d4b7,bsemi:204f,bsim:223d,bsime:22cd,bsol:5c,bsolb:29c5,bsolhsub:27c8,bull:2022,bullet:2022,bump:224e,bumpE:2aae,bumpe:224f,bumpeq:224f,cacute:107,cap:2229,capand:2a44,capbrcup:2a49,capcap:2a4b,capcup:2a47,capdot:2a40,caps:2229.fe00,caret:2041,caron:2c7,ccaps:2a4d,ccaron:10d,ccedil:e7,ccirc:109,ccups:2a4c,ccupssm:2a50,cdot:10b,cedil:b8,cemptyv:29b2,cent:a2,centerdot:b7,cfr:1d520,chcy:447,check:2713,checkmark:2713,chi:3c7,cir:25cb,cirE:29c3,circ:2c6,circeq:2257,circlearrowleft:21ba,circlearrowright:21bb,circledR:ae,circledS:24c8,circledast:229b,circledcirc:229a,circleddash:229d,cire:2257,cirfnint:2a10,cirmid:2aef,cirscir:29c2,clubs:2663,clubsuit:2663,colon:3a,colone:2254,coloneq:2254,comma:2c,commat:40,comp:2201,compfn:2218,complement:2201,complexes:2102,cong:2245,congdot:2a6d,conint:222e,copf:1d554,coprod:2210,copy:a9,copysr:2117,crarr:21b5,cross:2717,cscr:1d4b8,csub:2acf,csube:2ad1,csup:2ad0,csupe:2ad2,ctdot:22ef,cudarrl:2938,cudarrr:2935,cuepr:22de,cuesc:22df,cularr:21b6,cularrp:293d,cup:222a,cupbrcap:2a48,cupcap:2a46,cupcup:2a4a,cupdot:228d,cupor:2a45,cups:222a.fe00,curarr:21b7,curarrm:293c,curlyeqprec:22de,curlyeqsucc:22df,curlyvee:22ce,curlywedge:22cf,curren:a4,curvearrowleft:21b6,curvearrowright:21b7,cuvee:22ce,cuwed:22cf,cwconint:2232,cwint:2231,cylcty:232d,dArr:21d3,dHar:2965,dagger:2020,daleth:2138,darr:2193,dash:2010,dashv:22a3,dbkarow:290f,dblac:2dd,dcaron:10f,dcy:434,dd:2146,ddagger:2021,ddarr:21ca,ddotseq:2a77,deg:b0,delta:3b4,demptyv:29b1,dfisht:297f,dfr:1d521,dharl:21c3,dharr:21c2,diam:22c4,diamond:22c4,diamondsuit:2666,diams:2666,die:a8,digamma:3dd,disin:22f2,div:f7,divide:f7,divideontimes:22c7,divonx:22c7,djcy:452,dlcorn:231e,dlcrop:230d,dollar:24,dopf:1d555,dot:2d9,doteq:2250,doteqdot:2251,dotminus:2238,dotplus:2214,dotsquare:22a1,doublebarwedge:2306,downarrow:2193,downdownarrows:21ca,downharpoonleft:21c3,downharpoonright:21c2,drbkarow:2910,drcorn:231f,drcrop:230c,dscr:1d4b9,dscy:455,dsol:29f6,dstrok:111,dtdot:22f1,dtri:25bf,dtrif:25be,duarr:21f5,duhar:296f,dwangle:29a6,dzcy:45f,dzigrarr:27ff,eDDot:2a77,eDot:2251,eacute:e9,easter:2a6e,ecaron:11b,ecir:2256,ecirc:ea,ecolon:2255,ecy:44d,edot:117,ee:2147,efDot:2252,efr:1d522,eg:2a9a,egrave:e8,egs:2a96,egsdot:2a98,el:2a99,elinters:23e7,ell:2113,els:2a95,elsdot:2a97,emacr:113,empty:2205,emptyset:2205,emptyv:2205,emsp:2003,emsp13:2004,emsp14:2005,eng:14b,ensp:2002,eogon:119,eopf:1d556,epar:22d5,eparsl:29e3,eplus:2a71,epsi:3b5,epsilon:3b5,epsiv:3f5,eqcirc:2256,eqcolon:2255,eqsim:2242,eqslantgtr:2a96,eqslantless:2a95,equals:3d,equest:225f,equiv:2261,equivDD:2a78,eqvparsl:29e5,erDot:2253,erarr:2971,escr:212f,esdot:2250,esim:2242,eta:3b7,eth:f0,euml:eb,euro:20ac,excl:21,exist:2203,expectation:2130,exponentiale:2147,fallingdotseq:2252,fcy:444,female:2640,ffilig:fb03,fflig:fb00,ffllig:fb04,ffr:1d523,filig:fb01,fjlig:66.6a,flat:266d,fllig:fb02,fltns:25b1,fnof:192,fopf:1d557,forall:2200,fork:22d4,forkv:2ad9,fpartint:2a0d,frac12:bd,frac13:2153,frac14:bc,frac15:2155,frac16:2159,frac18:215b,frac23:2154,frac25:2156,frac34:be,frac35:2157,frac38:215c,frac45:2158,frac56:215a,frac58:215d,frac78:215e,frasl:2044,frown:2322,fscr:1d4bb,gE:2267,gEl:2a8c,gacute:1f5,gamma:3b3,gammad:3dd,gap:2a86,gbreve:11f,gcirc:11d,gcy:433,gdot:121,ge:2265,gel:22db,geq:2265,geqq:2267,geqslant:2a7e,ges:2a7e,gescc:2aa9,gesdot:2a80,gesdoto:2a82,gesdotol:2a84,gesl:22db.fe00,gesles:2a94,gfr:1d524,gg:226b,ggg:22d9,gimel:2137,gjcy:453,gl:2277,glE:2a92,gla:2aa5,glj:2aa4,gnE:2269,gnap:2a8a,gnapprox:2a8a,gne:2a88,gneq:2a88,gneqq:2269,gnsim:22e7,gopf:1d558,grave:60,gscr:210a,gsim:2273,gsime:2a8e,gsiml:2a90,gt:3e,gtcc:2aa7,gtcir:2a7a,gtdot:22d7,gtlPar:2995,gtquest:2a7c,gtrapprox:2a86,gtrarr:2978,gtrdot:22d7,gtreqless:22db,gtreqqless:2a8c,gtrless:2277,gtrsim:2273,gvertneqq:2269.fe00,gvnE:2269.fe00,hArr:21d4,hairsp:200a,half:bd,hamilt:210b,hardcy:44a,harr:2194,harrcir:2948,harrw:21ad,hbar:210f,hcirc:125,hearts:2665,heartsuit:2665,hellip:2026,hercon:22b9,hfr:1d525,hksearow:2925,hkswarow:2926,hoarr:21ff,homtht:223b,hookleftarrow:21a9,hookrightarrow:21aa,hopf:1d559,horbar:2015,hscr:1d4bd,hslash:210f,hstrok:127,hybull:2043,hyphen:2010,iacute:ed,ic:2063,icirc:ee,icy:438,iecy:435,iexcl:a1,iff:21d4,ifr:1d526,igrave:ec,ii:2148,iiiint:2a0c,iiint:222d,iinfin:29dc,iiota:2129,ijlig:133,imacr:12b,image:2111,imagline:2110,imagpart:2111,imath:131,imof:22b7,imped:1b5,in:2208,incare:2105,infin:221e,infintie:29dd,inodot:131,int:222b,intcal:22ba,integers:2124,intercal:22ba,intlarhk:2a17,intprod:2a3c,iocy:451,iogon:12f,iopf:1d55a,iota:3b9,iprod:2a3c,iquest:bf,iscr:1d4be,isin:2208,isinE:22f9,isindot:22f5,isins:22f4,isinsv:22f3,isinv:2208,it:2062,itilde:129,iukcy:456,iuml:ef,jcirc:135,jcy:439,jfr:1d527,jmath:237,jopf:1d55b,jscr:1d4bf,jsercy:458,jukcy:454,kappa:3ba,kappav:3f0,kcedil:137,kcy:43a,kfr:1d528,kgreen:138,khcy:445,kjcy:45c,kopf:1d55c,kscr:1d4c0,lAarr:21da,lArr:21d0,lAtail:291b,lBarr:290e,lE:2266,lEg:2a8b,lHar:2962,lacute:13a,laemptyv:29b4,lagran:2112,lambda:3bb,lang:27e8,langd:2991,langle:27e8,lap:2a85,laquo:ab,larr:2190,larrb:21e4,larrbfs:291f,larrfs:291d,larrhk:21a9,larrlp:21ab,larrpl:2939,larrsim:2973,larrtl:21a2,lat:2aab,latail:2919,late:2aad,lates:2aad.fe00,lbarr:290c,lbbrk:2772,lbrace:7b,lbrack:5b,lbrke:298b,lbrksld:298f,lbrkslu:298d,lcaron:13e,lcedil:13c,lceil:2308,lcub:7b,lcy:43b,ldca:2936,ldquo:201c,ldquor:201e,ldrdhar:2967,ldrushar:294b,ldsh:21b2,le:2264,leftarrow:2190,leftarrowtail:21a2,leftharpoondown:21bd,leftharpoonup:21bc,leftleftarrows:21c7,leftrightarrow:2194,leftrightarrows:21c6,leftrightharpoons:21cb,leftrightsquigarrow:21ad,leftthreetimes:22cb,leg:22da,leq:2264,leqq:2266,leqslant:2a7d,les:2a7d,lescc:2aa8,lesdot:2a7f,lesdoto:2a81,lesdotor:2a83,lesg:22da.fe00,lesges:2a93,lessapprox:2a85,lessdot:22d6,lesseqgtr:22da,lesseqqgtr:2a8b,lessgtr:2276,lesssim:2272,lfisht:297c,lfloor:230a,lfr:1d529,lg:2276,lgE:2a91,lhard:21bd,lharu:21bc,lharul:296a,lhblk:2584,ljcy:459,ll:226a,llarr:21c7,llcorner:231e,llhard:296b,lltri:25fa,lmidot:140,lmoust:23b0,lmoustache:23b0,lnE:2268,lnap:2a89,lnapprox:2a89,lne:2a87,lneq:2a87,lneqq:2268,lnsim:22e6,loang:27ec,loarr:21fd,lobrk:27e6,longleftarrow:27f5,longleftrightarrow:27f7,longmapsto:27fc,longrightarrow:27f6,looparrowleft:21ab,looparrowright:21ac,lopar:2985,lopf:1d55d,loplus:2a2d,lotimes:2a34,lowast:2217,lowbar:5f,loz:25ca,lozenge:25ca,lozf:29eb,lpar:28,lparlt:2993,lrarr:21c6,lrcorner:231f,lrhar:21cb,lrhard:296d,lrm:200e,lrtri:22bf,lsaquo:2039,lscr:1d4c1,lsh:21b0,lsim:2272,lsime:2a8d,lsimg:2a8f,lsqb:5b,lsquo:2018,lsquor:201a,lstrok:142,lt:3c,ltcc:2aa6,ltcir:2a79,ltdot:22d6,lthree:22cb,ltimes:22c9,ltlarr:2976,ltquest:2a7b,ltrPar:2996,ltri:25c3,ltrie:22b4,ltrif:25c2,lurdshar:294a,luruhar:2966,lvertneqq:2268.fe00,lvnE:2268.fe00,mDDot:223a,macr:af,male:2642,malt:2720,maltese:2720,map:21a6,mapsto:21a6,mapstodown:21a7,mapstoleft:21a4,mapstoup:21a5,marker:25ae,mcomma:2a29,mcy:43c,mdash:2014,measuredangle:2221,mfr:1d52a,mho:2127,micro:b5,mid:2223,midast:2a,midcir:2af0,middot:b7,minus:2212,minusb:229f,minusd:2238,minusdu:2a2a,mlcp:2adb,mldr:2026,mnplus:2213,models:22a7,mopf:1d55e,mp:2213,mscr:1d4c2,mstpos:223e,mu:3bc,multimap:22b8,mumap:22b8,nGg:22d9.338,nGt:226b.20d2,nGtv:226b.338,nLeftarrow:21cd,nLeftrightarrow:21ce,nLl:22d8.338,nLt:226a.20d2,nLtv:226a.338,nRightarrow:21cf,nVDash:22af,nVdash:22ae,nabla:2207,nacute:144,nang:2220.20d2,nap:2249,napE:2a70.338,napid:224b.338,napos:149,napprox:2249,natur:266e,natural:266e,naturals:2115,nbsp:a0,nbump:224e.338,nbumpe:224f.338,ncap:2a43,ncaron:148,ncedil:146,ncong:2247,ncongdot:2a6d.338,ncup:2a42,ncy:43d,ndash:2013,ne:2260,neArr:21d7,nearhk:2924,nearr:2197,nearrow:2197,nedot:2250.338,nequiv:2262,nesear:2928,nesim:2242.338,nexist:2204,nexists:2204,nfr:1d52b,ngE:2267.338,nge:2271,ngeq:2271,ngeqq:2267.338,ngeqslant:2a7e.338,nges:2a7e.338,ngsim:2275,ngt:226f,ngtr:226f,nhArr:21ce,nharr:21ae,nhpar:2af2,ni:220b,nis:22fc,nisd:22fa,niv:220b,njcy:45a,nlArr:21cd,nlE:2266.338,nlarr:219a,nldr:2025,nle:2270,nleftarrow:219a,nleftrightarrow:21ae,nleq:2270,nleqq:2266.338,nleqslant:2a7d.338,nles:2a7d.338,nless:226e,nlsim:2274,nlt:226e,nltri:22ea,nltrie:22ec,nmid:2224,nopf:1d55f,not:ac,notin:2209,notinE:22f9.338,notindot:22f5.338,notinva:2209,notinvb:22f7,notinvc:22f6,notni:220c,notniva:220c,notnivb:22fe,notnivc:22fd,npar:2226,nparallel:2226,nparsl:2afd.20e5,npart:2202.338,npolint:2a14,npr:2280,nprcue:22e0,npre:2aaf.338,nprec:2280,npreceq:2aaf.338,nrArr:21cf,nrarr:219b,nrarrc:2933.338,nrarrw:219d.338,nrightarrow:219b,nrtri:22eb,nrtrie:22ed,nsc:2281,nsccue:22e1,nsce:2ab0.338,nscr:1d4c3,nshortmid:2224,nshortparallel:2226,nsim:2241,nsime:2244,nsimeq:2244,nsmid:2224,nspar:2226,nsqsube:22e2,nsqsupe:22e3,nsub:2284,nsubE:2ac5.338,nsube:2288,nsubset:2282.20d2,nsubseteq:2288,nsubseteqq:2ac5.338,nsucc:2281,nsucceq:2ab0.338,nsup:2285,nsupE:2ac6.338,nsupe:2289,nsupset:2283.20d2,nsupseteq:2289,nsupseteqq:2ac6.338,ntgl:2279,ntilde:f1,ntlg:2278,ntriangleleft:22ea,ntrianglelefteq:22ec,ntriangleright:22eb,ntrianglerighteq:22ed,nu:3bd,num:23,numero:2116,numsp:2007,nvDash:22ad,nvHarr:2904,nvap:224d.20d2,nvdash:22ac,nvge:2265.20d2,nvgt:3e.20d2,nvinfin:29de,nvlArr:2902,nvle:2264.20d2,nvlt:3c.20d2,nvltrie:22b4.20d2,nvrArr:2903,nvrtrie:22b5.20d2,nvsim:223c.20d2,nwArr:21d6,nwarhk:2923,nwarr:2196,nwarrow:2196,nwnear:2927,oS:24c8,oacute:f3,oast:229b,ocir:229a,ocirc:f4,ocy:43e,odash:229d,odblac:151,odiv:2a38,odot:2299,odsold:29bc,oelig:153,ofcir:29bf,ofr:1d52c,ogon:2db,ograve:f2,ogt:29c1,ohbar:29b5,ohm:3a9,oint:222e,olarr:21ba,olcir:29be,olcross:29bb,oline:203e,olt:29c0,omacr:14d,omega:3c9,omicron:3bf,omid:29b6,ominus:2296,oopf:1d560,opar:29b7,operp:29b9,oplus:2295,or:2228,orarr:21bb,ord:2a5d,order:2134,orderof:2134,ordf:aa,ordm:ba,origof:22b6,oror:2a56,orslope:2a57,orv:2a5b,oscr:2134,oslash:f8,osol:2298,otilde:f5,otimes:2297,otimesas:2a36,ouml:f6,ovbar:233d,par:2225,para:b6,parallel:2225,parsim:2af3,parsl:2afd,part:2202,pcy:43f,percnt:25,period:2e,permil:2030,perp:22a5,pertenk:2031,pfr:1d52d,phi:3c6,phiv:3d5,phmmat:2133,phone:260e,pi:3c0,pitchfork:22d4,piv:3d6,planck:210f,planckh:210e,plankv:210f,plus:2b,plusacir:2a23,plusb:229e,pluscir:2a22,plusdo:2214,plusdu:2a25,pluse:2a72,plusmn:b1,plussim:2a26,plustwo:2a27,pm:b1,pointint:2a15,popf:1d561,pound:a3,pr:227a,prE:2ab3,prap:2ab7,prcue:227c,pre:2aaf,prec:227a,precapprox:2ab7,preccurlyeq:227c,preceq:2aaf,precnapprox:2ab9,precneqq:2ab5,precnsim:22e8,precsim:227e,prime:2032,primes:2119,prnE:2ab5,prnap:2ab9,prnsim:22e8,prod:220f,profalar:232e,profline:2312,profsurf:2313,prop:221d,propto:221d,prsim:227e,prurel:22b0,pscr:1d4c5,psi:3c8,puncsp:2008,qfr:1d52e,qint:2a0c,qopf:1d562,qprime:2057,qscr:1d4c6,quaternions:210d,quatint:2a16,quest:3f,questeq:225f,quot:22,rAarr:21db,rArr:21d2,rAtail:291c,rBarr:290f,rHar:2964,race:223d.331,racute:155,radic:221a,raemptyv:29b3,rang:27e9,rangd:2992,range:29a5,rangle:27e9,raquo:bb,rarr:2192,rarrap:2975,rarrb:21e5,rarrbfs:2920,rarrc:2933,rarrfs:291e,rarrhk:21aa,rarrlp:21ac,rarrpl:2945,rarrsim:2974,rarrtl:21a3,rarrw:219d,ratail:291a,ratio:2236,rationals:211a,rbarr:290d,rbbrk:2773,rbrace:7d,rbrack:5d,rbrke:298c,rbrksld:298e,rbrkslu:2990,rcaron:159,rcedil:157,rceil:2309,rcub:7d,rcy:440,rdca:2937,rdldhar:2969,rdquo:201d,rdquor:201d,rdsh:21b3,real:211c,realine:211b,realpart:211c,reals:211d,rect:25ad,reg:ae,rfisht:297d,rfloor:230b,rfr:1d52f,rhard:21c1,rharu:21c0,rharul:296c,rho:3c1,rhov:3f1,rightarrow:2192,rightarrowtail:21a3,rightharpoondown:21c1,rightharpoonup:21c0,rightleftarrows:21c4,rightleftharpoons:21cc,rightrightarrows:21c9,rightsquigarrow:219d,rightthreetimes:22cc,ring:2da,risingdotseq:2253,rlarr:21c4,rlhar:21cc,rlm:200f,rmoust:23b1,rmoustache:23b1,rnmid:2aee,roang:27ed,roarr:21fe,robrk:27e7,ropar:2986,ropf:1d563,roplus:2a2e,rotimes:2a35,rpar:29,rpargt:2994,rppolint:2a12,rrarr:21c9,rsaquo:203a,rscr:1d4c7,rsh:21b1,rsqb:5d,rsquo:2019,rsquor:2019,rthree:22cc,rtimes:22ca,rtri:25b9,rtrie:22b5,rtrif:25b8,rtriltri:29ce,ruluhar:2968,rx:211e,sacute:15b,sbquo:201a,sc:227b,scE:2ab4,scap:2ab8,scaron:161,sccue:227d,sce:2ab0,scedil:15f,scirc:15d,scnE:2ab6,scnap:2aba,scnsim:22e9,scpolint:2a13,scsim:227f,scy:441,sdot:22c5,sdotb:22a1,sdote:2a66,seArr:21d8,searhk:2925,searr:2198,searrow:2198,sect:a7,semi:3b,seswar:2929,setminus:2216,setmn:2216,sext:2736,sfr:1d530,sfrown:2322,sharp:266f,shchcy:449,shcy:448,shortmid:2223,shortparallel:2225,shy:ad,sigma:3c3,sigmaf:3c2,sigmav:3c2,sim:223c,simdot:2a6a,sime:2243,simeq:2243,simg:2a9e,simgE:2aa0,siml:2a9d,simlE:2a9f,simne:2246,simplus:2a24,simrarr:2972,slarr:2190,smallsetminus:2216,smashp:2a33,smeparsl:29e4,smid:2223,smile:2323,smt:2aaa,smte:2aac,smtes:2aac.fe00,softcy:44c,sol:2f,solb:29c4,solbar:233f,sopf:1d564,spades:2660,spadesuit:2660,spar:2225,sqcap:2293,sqcaps:2293.fe00,sqcup:2294,sqcups:2294.fe00,sqsub:228f,sqsube:2291,sqsubset:228f,sqsubseteq:2291,sqsup:2290,sqsupe:2292,sqsupset:2290,sqsupseteq:2292,squ:25a1,square:25a1,squarf:25aa,squf:25aa,srarr:2192,sscr:1d4c8,ssetmn:2216,ssmile:2323,sstarf:22c6,star:2606,starf:2605,straightepsilon:3f5,straightphi:3d5,strns:af,sub:2282,subE:2ac5,subdot:2abd,sube:2286,subedot:2ac3,submult:2ac1,subnE:2acb,subne:228a,subplus:2abf,subrarr:2979,subset:2282,subseteq:2286,subseteqq:2ac5,subsetneq:228a,subsetneqq:2acb,subsim:2ac7,subsub:2ad5,subsup:2ad3,succ:227b,succapprox:2ab8,succcurlyeq:227d,succeq:2ab0,succnapprox:2aba,succneqq:2ab6,succnsim:22e9,succsim:227f,sum:2211,sung:266a,sup:2283,sup1:b9,sup2:b2,sup3:b3,supE:2ac6,supdot:2abe,supdsub:2ad8,supe:2287,supedot:2ac4,suphsol:27c9,suphsub:2ad7,suplarr:297b,supmult:2ac2,supnE:2acc,supne:228b,supplus:2ac0,supset:2283,supseteq:2287,supseteqq:2ac6,supsetneq:228b,supsetneqq:2acc,supsim:2ac8,supsub:2ad4,supsup:2ad6,swArr:21d9,swarhk:2926,swarr:2199,swarrow:2199,swnwar:292a,szlig:df,target:2316,tau:3c4,tbrk:23b4,tcaron:165,tcedil:163,tcy:442,tdot:20db,telrec:2315,tfr:1d531,there4:2234,therefore:2234,theta:3b8,thetasym:3d1,thetav:3d1,thickapprox:2248,thicksim:223c,thinsp:2009,thkap:2248,thksim:223c,thorn:fe,tilde:2dc,times:d7,timesb:22a0,timesbar:2a31,timesd:2a30,tint:222d,toea:2928,top:22a4,topbot:2336,topcir:2af1,topf:1d565,topfork:2ada,tosa:2929,tprime:2034,trade:2122,triangle:25b5,triangledown:25bf,triangleleft:25c3,trianglelefteq:22b4,triangleq:225c,triangleright:25b9,trianglerighteq:22b5,tridot:25ec,trie:225c,triminus:2a3a,triplus:2a39,trisb:29cd,tritime:2a3b,trpezium:23e2,tscr:1d4c9,tscy:446,tshcy:45b,tstrok:167,twixt:226c,twoheadleftarrow:219e,twoheadrightarrow:21a0,uArr:21d1,uHar:2963,uacute:fa,uarr:2191,ubrcy:45e,ubreve:16d,ucirc:fb,ucy:443,udarr:21c5,udblac:171,udhar:296e,ufisht:297e,ufr:1d532,ugrave:f9,uharl:21bf,uharr:21be,uhblk:2580,ulcorn:231c,ulcorner:231c,ulcrop:230f,ultri:25f8,umacr:16b,uml:a8,uogon:173,uopf:1d566,uparrow:2191,updownarrow:2195,upharpoonleft:21bf,upharpoonright:21be,uplus:228e,upsi:3c5,upsih:3d2,upsilon:3c5,upuparrows:21c8,urcorn:231d,urcorner:231d,urcrop:230e,uring:16f,urtri:25f9,uscr:1d4ca,utdot:22f0,utilde:169,utri:25b5,utrif:25b4,uuarr:21c8,uuml:fc,uwangle:29a7,vArr:21d5,vBar:2ae8,vBarv:2ae9,vDash:22a8,vangrt:299c,varepsilon:3f5,varkappa:3f0,varnothing:2205,varphi:3d5,varpi:3d6,varpropto:221d,varr:2195,varrho:3f1,varsigma:3c2,varsubsetneq:228a.fe00,varsubsetneqq:2acb.fe00,varsupsetneq:228b.fe00,varsupsetneqq:2acc.fe00,vartheta:3d1,vartriangleleft:22b2,vartriangleright:22b3,vcy:432,vdash:22a2,vee:2228,veebar:22bb,veeeq:225a,vellip:22ee,verbar:7c,vert:7c,vfr:1d533,vltri:22b2,vnsub:2282.20d2,vnsup:2283.20d2,vopf:1d567,vprop:221d,vrtri:22b3,vscr:1d4cb,vsubnE:2acb.fe00,vsubne:228a.fe00,vsupnE:2acc.fe00,vsupne:228b.fe00,vzigzag:299a,wcirc:175,wedbar:2a5f,wedge:2227,wedgeq:2259,weierp:2118,wfr:1d534,wopf:1d568,wp:2118,wr:2240,wreath:2240,wscr:1d4cc,xcap:22c2,xcirc:25ef,xcup:22c3,xdtri:25bd,xfr:1d535,xhArr:27fa,xharr:27f7,xi:3be,xlArr:27f8,xlarr:27f5,xmap:27fc,xnis:22fb,xodot:2a00,xopf:1d569,xoplus:2a01,xotime:2a02,xrArr:27f9,xrarr:27f6,xscr:1d4cd,xsqcup:2a06,xuplus:2a04,xutri:25b3,xvee:22c1,xwedge:22c0,yacute:fd,yacy:44f,ycirc:177,ycy:44b,yen:a5,yfr:1d536,yicy:457,yopf:1d56a,yscr:1d4ce,yucy:44e,yuml:ff,zacute:17a,zcaron:17e,zcy:437,zdot:17c,zeetrf:2128,zeta:3b6,zfr:1d537,zhcy:436,zigrarr:21dd,zopf:1d56b,zscr:1d4cf,zwj:200d,zwnj:200c,';
var LEGACY_NAMES = ' AElig AMP Aacute Acirc Agrave Aring Atilde Auml COPY Ccedil ETH Eacute Ecirc Egrave Euml GT Iacute Icirc Igrave Iuml LT Ntilde Oacute Ocirc Ograve Oslash Otilde Ouml QUOT REG THORN Uacute Ucirc Ugrave Uuml Yacute aacute acirc acute aelig agrave amp aring atilde auml brvbar ccedil cedil cent copy curren deg divide eacute ecirc egrave eth euml frac12 frac14 frac34 gt iacute icirc iexcl igrave iquest iuml laquo lt macr micro middot nbsp not ntilde oacute ocirc ograve ordf ordm oslash otilde ouml para plusmn pound quot raquo reg sect shy sup1 sup2 sup3 szlig thorn times uacute ucirc ugrave uml uuml yacute yen yuml ';
function table(pairs) { var map = Object.create(null); for (var k in pairs) map[k] = pairs[k]; return map; }
var COMMON = table({ amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: '\u00A0', copy: '\u00A9', reg: '\u00AE',
                     hellip: '\u2026', mdash: '\u2014', ndash: '\u2013', middot: '\u00B7', times: '\u00D7', yen: '\u00A5',
                     laquo: '\u00AB', raquo: '\u00BB', ldquo: '\u201C', rdquo: '\u201D', lsquo: '\u2018', rsquo: '\u2019' });
var found = Object.create(null), foundCount = 0;

function entity(name) {
  var value = COMMON[name];
  if (value !== undefined) return value;
  value = found[name];
  if (value !== undefined) return value === null ? undefined : value;
  var at = ENTITY_DATA.indexOf(',' + name + ':');
  if (at < 0) value = null;
  else {
    var start = at + name.length + 2;
    value = String.fromCodePoint.apply(null, ENTITY_DATA.slice(start, ENTITY_DATA.indexOf(',', start)).split('.').map(function (h) {
      return parseInt(h, 16);
    }));
  }
  if (foundCount < 512) { found[name] = value; foundCount++; }
  return value === null ? undefined : value;
}
function isLegacy(name) { return LEGACY_NAMES.indexOf(' ' + name + ' ') >= 0; }

var C1 = { 0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026, 0x86: 0x2020, 0x87: 0x2021,
           0x88: 0x02C6, 0x89: 0x2030, 0x8A: 0x0160, 0x8B: 0x2039, 0x8C: 0x0152, 0x8E: 0x017D, 0x91: 0x2018,
           0x92: 0x2019, 0x93: 0x201C, 0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014, 0x98: 0x02DC,
           0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A, 0x9C: 0x0153, 0x9E: 0x017E, 0x9F: 0x0178 };
var XML_ENTITIES = table({ amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" });
var REFERENCE = /&(?:#(\d+);?|#[xX]([0-9a-fA-F]+);?|([A-Za-z][A-Za-z0-9]*)(;?))/g;

function numeric(code) {
  if (!(code > 0) || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF)) return '�';
  return String.fromCodePoint(C1[code] || code);
}

// HTML's rules: a known name with its semicolon; else the longest name that
// may come without one, unless, in an attribute, an alphanumeric or `=`
// follows it; else the text as written.
function decode(text, inAttribute, xml) {
  if (text.indexOf('&') < 0) return text;
  return text.replace(REFERENCE, function (whole, dec, hex, name, semi, offset, string) {
    if (dec !== undefined) return numeric(dec.length > 7 ? 0x110000 : parseInt(dec, 10));
    if (hex !== undefined) return numeric(hex.length > 6 ? 0x110000 : parseInt(hex, 16));
    if (xml) return semi && XML_ENTITIES[name] !== undefined ? XML_ENTITIES[name] : whole;
    var value = semi ? entity(name) : undefined;
    if (value !== undefined) return value;
    for (var n = Math.min(name.length, 6); n >= 2; n--) {
      var prefix = name.slice(0, n);
      if (!isLegacy(prefix)) continue;
      var rest = name.slice(n) + semi;
      if (inAttribute && /^[A-Za-z0-9=]/.test(rest + (string[offset + whole.length] || ''))) return whole;
      return entity(prefix) + rest;
    }
    return whole;
  });
}

// ---- Nodes --------------------------------------------------------------

var HTML_NS = 'http://www.w3.org/1999/xhtml', SVG_NS = 'http://www.w3.org/2000/svg',
    MATH_NS = 'http://www.w3.org/1998/Math/MathML';
var ELEMENT_NODE = 1, ATTRIBUTE_NODE = 2, TEXT_NODE = 3, CDATA_SECTION_NODE = 4, PROCESSING_INSTRUCTION_NODE = 7,
    COMMENT_NODE = 8, DOCUMENT_NODE = 9, DOCUMENT_TYPE_NODE = 10, DOCUMENT_FRAGMENT_NODE = 11;

function words(text) {
  var set = Object.create(null);
  text.split(' ').forEach(function (w) { set[w] = true; });
  return set;
}

var VOID = words('area base basefont bgsound br col embed frame hr img input keygen link meta param source track wbr');
var RAW_TEXT = words('script style xmp iframe noembed noframes noscript');
var SERIALIZED_RAW = words('style script xmp iframe noembed noframes plaintext noscript');

// Every tree change and attribute change moves this on: a live collection
// computes its members again only when it has moved.
var clock = 0;

// A static NodeList (querySelectorAll's): the array, with `item`. A node's
// childNodes is a plain array, kept in place as the tree changes.
function itemOf(index) { return this[index] === undefined ? null : this[index]; }
function nodeList(array) {
  hidden(array, 'item', itemOf);
  return array;
}
// Text, comments and doctypes have no children (LEAF); an element has none
// until one is put in it (NONE_YET): each a shared, frozen list, so most of
// a page's nodes make no array of their own.
var LEAF = Object.freeze([]), NONE_YET = Object.freeze([]);
var NO_ATTRIBUTES = Object.freeze([]);

function textOf(node) {
  if (node.nodeType === TEXT_NODE || node.nodeType === CDATA_SECTION_NODE) return node.data;
  var out = '', kids = node._kids;
  for (var i = 0; i < kids.length; i++) {
    var kid = kids[i];
    if (kid.nodeType === TEXT_NODE || kid.nodeType === CDATA_SECTION_NODE) out += kid.data;
    else if (kid.nodeType === ELEMENT_NODE) out += textOf(kid);
  }
  return out;
}

function detach(node) {
  var parent = node.parentNode;
  if (!parent) return;
  var kids = parent._kids, at = kids.indexOf(node);
  if (at >= 0) kids.splice(at, 1);
  node.parentNode = null;
  clock++;
}

// What `append`, `before` and the rest take: nodes, and strings as text.
function toNode(document, items) {
  if (items.length === 1 && typeof items[0] === 'object' && items[0] !== null && items[0].nodeType) return items[0];
  var fragment = new DocumentFragment(document);
  for (var i = 0; i < items.length; i++) {
    var item = items[i];
    fragment.appendChild(item !== null && typeof item === 'object' && item.nodeType ? item : document.createTextNode(String(item)));
  }
  return fragment;
}

function ownerOf(node) { return node.nodeType === DOCUMENT_NODE ? node : node.ownerDocument; }

// nodeType is each class's prototype's, not each node's own.
class Node {
  constructor(type, document) {
    this.ownerDocument = document;
    this.parentNode = null;
    // An element's and a leaf's lists are their prototype's until one is
    // put in an element (insertBefore).
    if (type === DOCUMENT_NODE || type === DOCUMENT_FRAGMENT_NODE) this._kids = [];
  }
  get childNodes() { if (this._kids === NONE_YET) this._kids = []; return this._kids; }
  get parentElement() { var p = this.parentNode; return p && p.nodeType === ELEMENT_NODE ? p : null; }
  get firstChild() { var k = this._kids; return k.length ? k[0] : null; }
  get lastChild() { var k = this._kids; return k.length ? k[k.length - 1] : null; }
  get nextSibling() { return sibling(this, 1, false); }
  get previousSibling() { return sibling(this, -1, false); }
  get nextElementSibling() { return sibling(this, 1, true); }
  get previousElementSibling() { return sibling(this, -1, true); }
  get isConnected() { var n = this; while (n.parentNode) n = n.parentNode; return n.nodeType === DOCUMENT_NODE; }
  get nodeValue() { return null; }
  set nodeValue(value) {}
  get textContent() { return null; }
  set textContent(value) {}
  hasChildNodes() { return this._kids.length > 0; }
  getRootNode() { var n = this; while (n.parentNode) n = n.parentNode; return n; }
  contains(node) {
    for (var n = node; n; n = n.parentNode) if (n === this) return true;
    return false;
  }
  appendChild(node) { return this.insertBefore(node, null); }
  insertBefore(node, reference) {
    if (!node || typeof node !== 'object' || !node.nodeType) throw new TypeError("Argument 1 ('node') to Node.insertBefore must be an instance of Node");
    if (this._kids === LEAF) throw domError('HierarchyRequestError', 'The operation would yield an incorrect node tree.');
    if (reference === undefined) reference = null;
    if (reference !== null && reference.parentNode !== this) throw domError('NotFoundError', 'The object can not be found here.');
    if (node.contains(this)) throw domError('HierarchyRequestError', 'The operation would yield an incorrect node tree.');
    if (node.nodeType === DOCUMENT_FRAGMENT_NODE) {
      var moving = node._kids.slice();
      for (var i = 0; i < moving.length; i++) this.insertBefore(moving[i], reference);
      return node;
    }
    if (node === reference) return node;
    detach(node);
    if (this._kids === NONE_YET) this._kids = [];
    var kids = this._kids;
    var at = reference === null ? kids.length : kids.indexOf(reference);
    if (at === kids.length) kids.push(node); else kids.splice(at, 0, node);
    node.parentNode = this;
    adopt(node, ownerOf(this));
    clock++;
    return node;
  }
  removeChild(node) {
    if (!node || node.parentNode !== this) throw domError('NotFoundError', 'The object can not be found here.');
    detach(node);
    return node;
  }
  replaceChild(node, old) {
    if (!old || old.parentNode !== this) throw domError('NotFoundError', 'The object can not be found here.');
    if (node === old) return old;
    var next = old.nextSibling === node ? node.nextSibling : old.nextSibling;
    detach(old);
    this.insertBefore(node, next);
    return old;
  }
  cloneNode(deep) {
    var copy = shallowCopy(this);
    if (deep) {
      var kids = this._kids;
      for (var i = 0; i < kids.length; i++) copy.appendChild(kids[i].cloneNode(true));
    }
    return copy;
  }
  isSameNode(node) { return this === node; }
  normalize() {
    var kids = this._kids;
    for (var i = 0; i < kids.length; i++) {
      var kid = kids[i];
      if (kid.nodeType === TEXT_NODE) {
        while (i + 1 < kids.length && kids[i + 1].nodeType === TEXT_NODE) { kid.data += kids[i + 1].data; detach(kids[i + 1]); }
        if (kid.data === '') { detach(kid); i--; }
      } else if (kid.nodeType === ELEMENT_NODE) kid.normalize();
    }
  }
}
// Not structured-cloneable, as a platform's nodes are not (the web globals' structuredClone reads this mark).
Object.defineProperty(Node.prototype, Symbol.for('clash.platformObject'), { value: true });
[['ELEMENT_NODE', 1], ['ATTRIBUTE_NODE', 2], ['TEXT_NODE', 3], ['CDATA_SECTION_NODE', 4], ['PROCESSING_INSTRUCTION_NODE', 7],
 ['COMMENT_NODE', 8], ['DOCUMENT_NODE', 9], ['DOCUMENT_TYPE_NODE', 10], ['DOCUMENT_FRAGMENT_NODE', 11]].forEach(function (pair) {
  Object.defineProperty(Node, pair[0], { value: pair[1] });
  Object.defineProperty(Node.prototype, pair[0], { value: pair[1] });
});

function sibling(node, step, elementsOnly) {
  var parent = node.parentNode;
  if (!parent) return null;
  var kids = parent._kids;
  for (var i = kids.indexOf(node) + step; i >= 0 && i < kids.length; i += step) {
    if (!elementsOnly || kids[i].nodeType === ELEMENT_NODE) return kids[i];
  }
  return null;
}

function adopt(node, document) {
  if (!document || node.ownerDocument === document) return;
  node.ownerDocument = document;
  var kids = node._kids;
  for (var i = 0; i < kids.length; i++) adopt(kids[i], document);
}

function shallowCopy(node) {
  var document = ownerOf(node);
  switch (node.nodeType) {
    case ELEMENT_NODE: {
      return new Element(document, node.localName, node.namespaceURI, node.prefix,
                         node._attributes.map(function (a) { return { name: a.name, value: a.value }; }));
    }
    case TEXT_NODE: return new Text(document, node.data);
    case CDATA_SECTION_NODE: return new CDATASection(document, node.data);
    case COMMENT_NODE: return new Comment(document, node.data);
    case PROCESSING_INSTRUCTION_NODE: return new ProcessingInstruction(document, node.target, node.data);
    case DOCUMENT_TYPE_NODE: return new DocumentType(document, node.name, node.publicId, node.systemId);
    case DOCUMENT_FRAGMENT_NODE: return new DocumentFragment(document);
    case DOCUMENT_NODE: return new Document(node._html, node.contentType);
  }
  throw domError('NotSupportedError', 'The node can not be cloned.');
}

class CharacterData extends Node {
  constructor(type, document, data) { super(type, document); this.data = String(data); }
  get nodeValue() { return this.data; }
  set nodeValue(value) { this.data = value === null ? '' : String(value); }
  get textContent() { return this.data; }
  set textContent(value) { this.data = value === null ? '' : String(value); }
  get length() { return this.data.length; }
  appendData(data) { this.data += String(data); }
  substringData(offset, count) { return this.data.substr(offset, count); }
  before() { if (this.parentNode) this.parentNode.insertBefore(toNode(this.ownerDocument, arguments), this); }
  after() { if (this.parentNode) this.parentNode.insertBefore(toNode(this.ownerDocument, arguments), this.nextSibling); }
  replaceWith() { if (this.parentNode) { var p = this.parentNode, next = this.nextSibling; detach(this); p.insertBefore(toNode(this.ownerDocument, arguments), next); } }
  remove() { detach(this); }
  get nextElementSibling() { return sibling(this, 1, true); }
}
class Text extends CharacterData {
  constructor(document, data) { super(TEXT_NODE, document, data); }
  get nodeName() { return '#text'; }
  get wholeText() { return this.data; }
}
class CDATASection extends CharacterData {
  constructor(document, data) { super(CDATA_SECTION_NODE, document, data); }
  get nodeName() { return '#cdata-section'; }
}
class Comment extends CharacterData {
  constructor(document, data) { super(COMMENT_NODE, document, data); }
  get nodeName() { return '#comment'; }
}
class ProcessingInstruction extends CharacterData {
  constructor(document, target, data) { super(PROCESSING_INSTRUCTION_NODE, document, data); this.target = target; }
  get nodeName() { return this.target; }
}
class DocumentType extends Node {
  constructor(document, name, publicId, systemId) {
    super(DOCUMENT_TYPE_NODE, document);
    this.name = name; this.publicId = publicId || ''; this.systemId = systemId || '';
  }
  get nodeName() { return this.name; }
  remove() { detach(this); }
}

// ParentNode: what elements, documents and fragments share.
var parentNode = {
  get children() { var self = this; return liveCollection(function () { return self._kids.filter(isElement); }); },
  get childElementCount() { return this._kids.filter(isElement).length; },
  get firstElementChild() { var k = this._kids; for (var i = 0; i < k.length; i++) if (k[i].nodeType === ELEMENT_NODE) return k[i]; return null; },
  get lastElementChild() { var k = this._kids; for (var i = k.length - 1; i >= 0; i--) if (k[i].nodeType === ELEMENT_NODE) return k[i]; return null; },
  append: function append() { this.insertBefore(toNode(ownerOf(this), arguments), null); },
  prepend: function prepend() { this.insertBefore(toNode(ownerOf(this), arguments), this.firstChild); },
  replaceChildren: function replaceChildren() {
    var node = toNode(ownerOf(this), arguments);
    while (this._kids.length) detach(this._kids[0]);
    this.insertBefore(node, null);
  },
  querySelector: function querySelector(selectors) { var all = select(this, selectors, true); return all.length ? all[0] : null; },
  querySelectorAll: function querySelectorAll(selectors) { return nodeList(select(this, selectors, false)); },
  getElementsByTagName: function getElementsByTagName(name) {
    var self = this, wanted = String(name), lower = wanted.toLowerCase();
    return liveCollection(function () {
      return descendants(self, function (e) {
        return wanted === '*' || (e.namespaceURI === HTML_NS && e.ownerDocument._html ? e.localName === lower : e.localName === wanted);
      });
    });
  },
  getElementsByClassName: function getElementsByClassName(names) {
    var self = this, wanted = String(names).split(/[\t\n\f\r ]+/).filter(Boolean);
    return liveCollection(function () {
      if (!wanted.length) return [];
      return descendants(self, function (e) {
        var classes = classesOf(e);
        return wanted.every(function (c) { return classes.indexOf(c) >= 0; });
      });
    });
  },
};

function isElement(node) { return node.nodeType === ELEMENT_NODE; }

function mix(target, source) {
  Object.getOwnPropertyNames(source).forEach(function (key) {
    Object.defineProperty(target, key, Object.getOwnPropertyDescriptor(source, key));
  });
}

function descendants(root, test) {
  var out = [];
  (function walk(node) {
    var kids = node._kids;
    for (var i = 0; i < kids.length; i++) {
      var kid = kids[i];
      if (kid.nodeType !== ELEMENT_NODE) continue;
      if (test(kid)) out.push(kid);
      walk(kid);
    }
  })(root);
  return out;
}

// HTMLCollection: live, recomputed only after the tree or an attribute changed.
function liveCollection(compute) {
  var cache = null, at = -1;
  function items() { if (at !== clock) { cache = compute(); at = clock; } return cache; }
  var methods = {
    item: function item(index) { var list = items(); return list[index] === undefined ? null : list[index]; },
    namedItem: function namedItem(name) {
      var list = items();
      for (var i = 0; i < list.length; i++) if (list[i].getAttribute('id') === name || list[i].getAttribute('name') === name) return list[i];
      return null;
    },
  };
  return new Proxy(methods, {
    get: function (target, key) {
      if (key === 'length') return items().length;
      if (typeof key === 'string' && /^(0|[1-9]\d*)$/.test(key)) return items()[Number(key)];
      if (key === Symbol.iterator) return function () { return items().slice()[Symbol.iterator](); };
      if (Object.prototype.hasOwnProperty.call(target, key)) return target[key];
      // Not an HTMLCollection's, but a script that calls them on one gets
      // what the snapshot's array does rather than a TypeError.
      if (typeof key === 'string' && typeof Array.prototype[key] === 'function') {
        return function () { var list = items().slice(); return Array.prototype[key].apply(list, arguments); };
      }
      return undefined;
    },
    has: function (target, key) {
      if (key === 'length') return true;
      if (typeof key === 'string' && /^(0|[1-9]\d*)$/.test(key)) return Number(key) < items().length;
      return key in target;
    },
    ownKeys: function () { return items().map(function (x, i) { return String(i); }).concat(['length']); },
    getOwnPropertyDescriptor: function (target, key) {
      if (key === 'length') return { value: items().length, writable: false, enumerable: false, configurable: true };
      if (typeof key === 'string' && /^(0|[1-9]\d*)$/.test(key) && Number(key) < items().length) {
        return { value: items()[Number(key)], writable: false, enumerable: true, configurable: true };
      }
      return undefined;
    },
    set: function () { return true; },
  });
}

class DocumentFragment extends Node {
  constructor(document) { super(DOCUMENT_FRAGMENT_NODE, document); }
  get nodeName() { return '#document-fragment'; }
  get textContent() { return textOf(this); }
  set textContent(value) { setText(this, value); }
  getElementById(id) { return byId(this, id); }
}
mix(DocumentFragment.prototype, parentNode);

function setText(node, value) {
  while (node._kids.length) detach(node._kids[0]);
  var text = value === null || value === undefined ? '' : String(value);
  if (text !== '') node.appendChild(new Text(ownerOf(node), text));
}

function byId(root, id) {
  var wanted = String(id), found = null;
  (function walk(node) {
    var kids = node._kids;
    for (var i = 0; i < kids.length && !found; i++) {
      var kid = kids[i];
      if (kid.nodeType !== ELEMENT_NODE) continue;
      if (kid.getAttribute('id') === wanted) { found = kid; return; }
      walk(kid);
    }
  })(root);
  return found;
}

// Whether whitespace-separated `list` holds `token`, without splitting it.
function hasToken(list, token) {
  if (!list || !token) return false;
  var at = list.indexOf(token);
  while (at >= 0) {
    var before = at === 0 ? 32 : list.charCodeAt(at - 1), after = at + token.length === list.length ? 32 : list.charCodeAt(at + token.length);
    if (isSpace(before) && isSpace(after)) return true;
    at = list.indexOf(token, at + 1);
  }
  return false;
}

function classesOf(element) {
  var value = element.getAttribute('class');
  return value ? value.split(/[\t\n\f\r ]+/).filter(Boolean) : [];
}

function camelToData(name) { return 'data-' + name.replace(/[A-Z]/g, function (c) { return '-' + c.toLowerCase(); }); }
function dataToCamel(name) { return name.slice(5).replace(/-([a-z])/g, function (m, c) { return c.toUpperCase(); }); }
function cssName(name) {
  if (name === 'cssFloat') return 'float';
  return name.indexOf('-') >= 0 ? name : name.replace(/[A-Z]/g, function (c) { return '-' + c.toLowerCase(); });
}

function parseDeclarations(text) {
  var out = [];
  String(text || '').split(';').forEach(function (part) {
    var at = part.indexOf(':');
    if (at < 0) return;
    var name = part.slice(0, at).trim().toLowerCase(), value = part.slice(at + 1).trim(), priority = '';
    var important = /\s*!\s*important\s*$/i;
    if (important.test(value)) { priority = 'important'; value = value.replace(important, ''); }
    if (name && value) out.push({ name: name, value: value, priority: priority });
  });
  return out;
}

function styleOf(element) {
  function read() { return parseDeclarations(element.getAttribute('style')); }
  function write(list) {
    element.setAttribute('style', list.map(function (d) { return d.name + ': ' + d.value + (d.priority ? ' !important' : '') + ';'; }).join(' '));
  }
  var api = {
    getPropertyValue: function (name) { var d = read().filter(function (x) { return x.name === String(name).toLowerCase(); }); return d.length ? d[d.length - 1].value : ''; },
    getPropertyPriority: function (name) { var d = read().filter(function (x) { return x.name === String(name).toLowerCase(); }); return d.length ? d[d.length - 1].priority : ''; },
    setProperty: function (name, value, priority) {
      name = String(name).toLowerCase();
      var list = read().filter(function (x) { return x.name !== name; });
      if (value !== null && value !== undefined && String(value) !== '') list.push({ name: name, value: String(value), priority: priority ? 'important' : '' });
      write(list);
    },
    removeProperty: function (name) {
      name = String(name).toLowerCase();
      var list = read(), old = api.getPropertyValue(name);
      write(list.filter(function (x) { return x.name !== name; }));
      return old;
    },
    item: function (index) { var d = read()[index]; return d ? d.name : ''; },
  };
  return new Proxy(api, {
    get: function (target, key) {
      if (key === 'cssText') return read().map(function (d) { return d.name + ': ' + d.value + (d.priority ? ' !important' : '') + ';'; }).join(' ');
      if (key === 'length') return read().length;
      if (typeof key !== 'string') return undefined;
      if (Object.prototype.hasOwnProperty.call(target, key)) return target[key];
      return api.getPropertyValue(cssName(key));
    },
    set: function (target, key, value) {
      if (key === 'cssText') { write(parseDeclarations(value)); return true; }
      if (typeof key === 'string') api.setProperty(cssName(key), value);
      return true;
    },
  });
}

function tokenList(element, attribute) {
  function read() { var v = element.getAttribute(attribute); return v ? v.split(/[\t\n\f\r ]+/).filter(Boolean) : []; }
  function write(list) { element.setAttribute(attribute, list.join(' ')); }
  function check(token) {
    token = String(token);
    if (token === '') throw domError('SyntaxError', 'The token must not be empty.');
    if (/[\t\n\f\r ]/.test(token)) throw domError('InvalidCharacterError', 'The token must not contain whitespace.');
    return token;
  }
  var api = {
    contains: function (token) { return read().indexOf(String(token)) >= 0; },
    add: function () {
      var list = read();
      for (var i = 0; i < arguments.length; i++) { var t = check(arguments[i]); if (list.indexOf(t) < 0) list.push(t); }
      write(list);
    },
    remove: function () {
      var drop = Array.prototype.map.call(arguments, check);
      write(read().filter(function (t) { return drop.indexOf(t) < 0; }));
    },
    toggle: function (token, force) {
      token = check(token);
      var has = api.contains(token);
      if (has && force !== true) { api.remove(token); return false; }
      if (!has && force !== false) { api.add(token); return true; }
      return has;
    },
    replace: function (old, token) {
      old = check(old); token = check(token);
      var list = read(), at = list.indexOf(old);
      if (at < 0) return false;
      list.splice(at, 1, token);
      write(list.filter(function (t, i) { return list.indexOf(t) === i; }));
      return true;
    },
    item: function (index) { var list = read(); return index < list.length ? list[index] : null; },
    forEach: function (callback, self) { read().forEach(callback, self); },
    toString: function () { return element.getAttribute(attribute) || ''; },
    supports: function () { return true; },
  };
  return new Proxy(api, {
    get: function (target, key) {
      if (key === 'length') return read().length;
      if (key === 'value') return element.getAttribute(attribute) || '';
      if (key === Symbol.iterator) return function () { return read()[Symbol.iterator](); };
      if (typeof key === 'string' && /^(0|[1-9]\d*)$/.test(key)) return read()[Number(key)];
      return target[key];
    },
    set: function (target, key, value) { if (key === 'value') element.setAttribute(attribute, String(value)); return true; },
  });
}

function datasetOf(element) {
  return new Proxy({}, {
    get: function (target, key) {
      if (typeof key !== 'string') return undefined;
      var value = element.getAttribute(camelToData(key));
      return value === null ? undefined : value;
    },
    set: function (target, key, value) { if (typeof key === 'string') element.setAttribute(camelToData(key), String(value)); return true; },
    has: function (target, key) { return typeof key === 'string' && element.hasAttribute(camelToData(key)); },
    deleteProperty: function (target, key) { if (typeof key === 'string') element.removeAttribute(camelToData(key)); return true; },
    ownKeys: function () {
      return element._attributes.filter(function (a) { return /^data-/.test(a.name); }).map(function (a) { return dataToCamel(a.name); });
    },
    getOwnPropertyDescriptor: function (target, key) {
      if (typeof key !== 'string' || !element.hasAttribute(camelToData(key))) return undefined;
      return { value: element.getAttribute(camelToData(key)), writable: true, enumerable: true, configurable: true };
    },
  });
}

class Element extends Node {
  constructor(document, localName, namespace, prefix, attributes) {
    super(ELEMENT_NODE, document);
    this.localName = localName;
    if (namespace !== undefined && namespace !== HTML_NS) this.namespaceURI = namespace;
    if (prefix) this.prefix = prefix;
    this._attributes = attributes && attributes.length ? attributes : NO_ATTRIBUTES;
  }
  get _isHTML() { return this.namespaceURI === HTML_NS && this.ownerDocument && this.ownerDocument._html; }
  get qualifiedName() { return this.prefix ? this.prefix + ':' + this.localName : this.localName; }
  get tagName() { return this._isHTML ? this.qualifiedName.toUpperCase() : this.qualifiedName; }
  get nodeName() { return this.tagName; }
  _name(name) { name = String(name); return this._isHTML ? name.toLowerCase() : name; }
  _find(name) {
    name = this._name(name);
    var list = this._attributes;
    for (var i = 0; i < list.length; i++) if (list[i].name === name) return list[i];
    return null;
  }
  getAttribute(name) { var a = this._find(name); return a ? a.value : null; }
  getAttributeNS(namespace, name) { return this.getAttribute(name); }
  hasAttribute(name) { return this._find(name) !== null; }
  hasAttributes() { return this._attributes.length > 0; }
  getAttributeNames() { return this._attributes.map(function (a) { return a.name; }); }
  setAttribute(name, value) {
    name = String(name);
    if (!/^[^\t\n\f\r \/>"'=]+$/.test(name)) throw domError('InvalidCharacterError', "Invalid qualified name: '" + name + "'");
    var a = this._find(name);
    if (a) a.value = String(value);
    else {
      if (this._attributes === NO_ATTRIBUTES) this._attributes = [];
      this._attributes.push({ name: this._name(name), value: String(value) });
    }
    clock++;
  }
  setAttributeNS(namespace, name, value) { this.setAttribute(name, value); }
  removeAttribute(name) {
    var a = this._find(name);
    if (a) { this._attributes.splice(this._attributes.indexOf(a), 1); clock++; }
  }
  toggleAttribute(name, force) {
    var has = this.hasAttribute(name);
    if (has && force !== true) { this.removeAttribute(name); return false; }
    if (!has && force !== false) { this.setAttribute(name, ''); return true; }
    return has;
  }
  get attributes() {
    var self = this;
    var list = this._attributes.map(function (a) {
      return { name: a.name, localName: a.name, value: a.value, nodeName: a.name, nodeValue: a.value, nodeType: ATTRIBUTE_NODE,
               ownerElement: self, specified: true, namespaceURI: null, prefix: null };
    });
    nodeList(list);
    hidden(list, 'getNamedItem', function (name) { var a = self._find(name); return a ? list[self._attributes.indexOf(a)] : null; });
    return list;
  }
  get id() { return this.getAttribute('id') || ''; }
  set id(value) { this.setAttribute('id', value); }
  get className() { return this.getAttribute('class') || ''; }
  set className(value) { this.setAttribute('class', value); }
  get classList() { return tokenList(this, 'class'); }
  get relList() { return tokenList(this, 'rel'); }
  get dataset() { return datasetOf(this); }
  get style() { return styleOf(this); }
  get textContent() { return textOf(this); }
  set textContent(value) { setText(this, value); }
  get innerText() { return textOf(this); }
  set innerText(value) { setText(this, value); }
  get outerText() { return textOf(this); }
  get text() { return textOf(this); }
  set text(value) { setText(this, value); }
  get innerHTML() { return serializeChildren(this, this.ownerDocument._html); }
  set innerHTML(html) {
    var fragment = parseFragment(this, html === null ? '' : String(html));
    while (this._kids.length) detach(this._kids[0]);
    this.insertBefore(fragment, null);
  }
  get outerHTML() { return serialize(this, this.ownerDocument._html); }
  set outerHTML(html) {
    var parent = this.parentNode;
    if (!parent) return;
    if (parent.nodeType === DOCUMENT_NODE) throw domError('NoModificationAllowedError', 'Cannot set outerHTML on the document element.');
    var context = parent.nodeType === ELEMENT_NODE ? parent : this.ownerDocument.createElement('body');
    var fragment = parseFragment(context, html === null ? '' : String(html)), next = this.nextSibling;
    detach(this);
    parent.insertBefore(fragment, next);
  }
  insertAdjacentHTML(position, html) {
    var where = String(position).toLowerCase(), context = where === 'beforebegin' || where === 'afterend' ? this.parentNode : this;
    if (!context || context.nodeType === DOCUMENT_NODE) {
      if (where === 'beforebegin' || where === 'afterend') throw domError('NoModificationAllowedError', 'The element has no parent.');
    }
    insertAdjacent(this, where, parseFragment(context.nodeType === ELEMENT_NODE ? context : this.ownerDocument.createElement('body'), String(html)));
  }
  insertAdjacentElement(position, element) { return insertAdjacent(this, String(position).toLowerCase(), element); }
  insertAdjacentText(position, text) { insertAdjacent(this, String(position).toLowerCase(), this.ownerDocument.createTextNode(String(text))); }
  before() { if (this.parentNode) this.parentNode.insertBefore(toNode(this.ownerDocument, arguments), this); }
  after() { if (this.parentNode) this.parentNode.insertBefore(toNode(this.ownerDocument, arguments), this.nextSibling); }
  replaceWith() {
    if (!this.parentNode) return;
    var parent = this.parentNode, next = this.nextSibling;
    var node = toNode(this.ownerDocument, arguments);
    if (node === next) next = next.nextSibling;
    detach(this);
    parent.insertBefore(node, next);
  }
  remove() { detach(this); }
  matches(selectors) { return matchesSelectors(this, compile(selectors), this); }
  webkitMatchesSelector(selectors) { return this.matches(selectors); }
  closest(selectors) {
    var groups = compile(selectors);
    for (var n = this; n && n.nodeType === ELEMENT_NODE; n = n.parentNode) if (matchesSelectors(n, groups, this)) return n;
    return null;
  }
  get content() {
    if (this.localName !== 'template') return undefined;
    var fragment = new DocumentFragment(this.ownerDocument);
    this._kids.slice().forEach(function (kid) { fragment.appendChild(kid.cloneNode(true)); });
    return fragment;
  }
  get hidden() { return this.hasAttribute('hidden'); }
  set hidden(value) { this.toggleAttribute('hidden', !!value); }
}
mix(Element.prototype, parentNode);

// IDL attributes that only reflect a content attribute of the same name.
['src', 'href', 'type', 'name', 'rel', 'content', 'alt', 'lang', 'dir', 'title', 'placeholder', 'action', 'method',
 'target', 'charset', 'width', 'height', 'value', 'media', 'role', 'slot', 'srcset', 'sizes', 'integrity', 'crossOrigin',
 'referrerPolicy', 'loading', 'poster', 'label', 'httpEquiv', 'htmlFor', 'colSpan', 'rowSpan'].forEach(function (key) {
  var attribute = { crossOrigin: 'crossorigin', referrerPolicy: 'referrerpolicy', httpEquiv: 'http-equiv', htmlFor: 'for',
                    colSpan: 'colspan', rowSpan: 'rowspan' }[key] || key;
  if (key === 'title') {
    Object.defineProperty(Element.prototype, key, {
      get: function () { return this.getAttribute('title') || ''; },
      set: function (v) { this.setAttribute('title', v); }, configurable: true,
    });
    return;
  }
  Object.defineProperty(Element.prototype, key, {
    get: function () { var v = this.getAttribute(attribute); return v === null ? '' : v; },
    set: function (v) { this.setAttribute(attribute, v); }, configurable: true,
  });
});
['async', 'defer', 'disabled', 'checked', 'selected', 'required', 'readOnly', 'multiple', 'autoplay', 'controls', 'loop',
 'muted', 'open', 'noModule', 'playsInline'].forEach(function (key) {
  var attribute = key.toLowerCase();
  Object.defineProperty(Element.prototype, key, {
    get: function () { return this.hasAttribute(attribute); },
    set: function (v) { this.toggleAttribute(attribute, !!v); }, configurable: true,
  });
});

function insertAdjacent(element, where, node) {
  switch (where) {
    case 'beforebegin': if (!element.parentNode) return null; element.parentNode.insertBefore(node, element); break;
    case 'afterbegin': element.insertBefore(node, element.firstChild); break;
    case 'beforeend': element.insertBefore(node, null); break;
    case 'afterend': if (!element.parentNode) return null; element.parentNode.insertBefore(node, element.nextSibling); break;
    default: throw domError('SyntaxError', "'" + where + "' is not a valid position.");
  }
  return node;
}

class Document extends Node {
  constructor(html, contentType) {
    super(DOCUMENT_NODE, null);
    this._html = html;
    this.contentType = contentType || (html ? 'text/html' : 'application/xml');
  }
  get nodeName() { return '#document'; }
  get documentElement() { return this.firstElementChild; }
  get doctype() { var k = this._kids; for (var i = 0; i < k.length; i++) if (k[i].nodeType === DOCUMENT_TYPE_NODE) return k[i]; return null; }
  get head() { return childNamed(this.documentElement, 'head'); }
  get body() { return childNamed(this.documentElement, 'body') || childNamed(this.documentElement, 'frameset'); }
  get title() {
    var title = descendants(this, function (e) { return e.localName === 'title'; })[0];
    return title ? textOf(title).replace(/[\t\n\f\r ]+/g, ' ').trim() : '';
  }
  set title(value) {
    var title = descendants(this, function (e) { return e.localName === 'title'; })[0];
    if (!title) {
      var head = this.head;
      if (!head) return;
      title = this.createElement('title');
      head.appendChild(title);
    }
    title.textContent = value;
  }
  get characterSet() { return 'UTF-8'; }
  get charset() { return 'UTF-8'; }
  get compatMode() { return 'CSS1Compat'; }
  get textContent() { return null; }
  createElement(name) {
    name = String(name);
    if (!/^[A-Za-z_:][^\t\n\f\r \/>]*$/.test(name)) throw domError('InvalidCharacterError', "Invalid qualified name: '" + name + "'");
    return new Element(this, this._html ? name.toLowerCase() : name, this._html || this.contentType === 'application/xhtml+xml' ? HTML_NS : null);
  }
  createElementNS(namespace, qualifiedName) {
    var parts = String(qualifiedName).split(':');
    return new Element(this, parts.length > 1 ? parts[1] : parts[0], namespace === undefined ? null : namespace, parts.length > 1 ? parts[0] : null);
  }
  createTextNode(data) { return new Text(this, data); }
  createComment(data) { return new Comment(this, data); }
  createCDATASection(data) { return new CDATASection(this, data); }
  createDocumentFragment() { return new DocumentFragment(this); }
  createProcessingInstruction(target, data) { return new ProcessingInstruction(this, target, data); }
  importNode(node, deep) { var copy = node.cloneNode(!!deep); adopt(copy, this); return copy; }
  adoptNode(node) { detach(node); adopt(node, this); return node; }
  getElementById(id) { return byId(this, id); }
  getElementsByName(name) { var self = this; return liveCollection(function () { return descendants(self, function (e) { return e.getAttribute('name') === String(name); }); }); }
  get scripts() { return this.getElementsByTagName('script'); }
  get images() { return this.getElementsByTagName('img'); }
  get forms() { return this.getElementsByTagName('form'); }
  get links() { var self = this; return liveCollection(function () { return descendants(self, function (e) { return (e.localName === 'a' || e.localName === 'area') && e.hasAttribute('href'); }); }); }
}
mix(Document.prototype, parentNode);

function childNamed(element, name) {
  if (!element) return null;
  var k = element._kids;
  for (var i = 0; i < k.length; i++) if (k[i].nodeType === ELEMENT_NODE && k[i].localName === name && k[i].namespaceURI === HTML_NS) return k[i];
  return null;
}

[[Element, ELEMENT_NODE], [Text, TEXT_NODE], [CDATASection, CDATA_SECTION_NODE], [ProcessingInstruction, PROCESSING_INSTRUCTION_NODE],
 [Comment, COMMENT_NODE], [Document, DOCUMENT_NODE], [DocumentType, DOCUMENT_TYPE_NODE], [DocumentFragment, DOCUMENT_FRAGMENT_NODE]].forEach(function (pair) {
  Object.defineProperty(pair[0].prototype, 'nodeType', { value: pair[1], configurable: true });
});
// An element's namespace and prefix are its own only when they are not HTML's and none.
Element.prototype.namespaceURI = HTML_NS;
Element.prototype.prefix = null;
Element.prototype._kids = NONE_YET;
CharacterData.prototype._kids = LEAF;
DocumentType.prototype._kids = LEAF;

// ---- Serializing ----------------------------------------------------------
// HTML's fragment serialization (https://html.spec.whatwg.org/#serialising-html-fragments)
// for an HTML document; XML's (the DOM Parsing spec's, well-formedness not
// checked) for the rest and XMLSerializer.

function escapeText(text) {
  return text.replace(/[&<> ]/g, function (c) { return c === '&' ? '&amp;' : c === '<' ? '&lt;' : c === '>' ? '&gt;' : '&nbsp;'; });
}
function escapeAttribute(text) {
  return text.replace(/[&"<> ]/g, function (c) {
    return c === '&' ? '&amp;' : c === '"' ? '&quot;' : c === '<' ? '&lt;' : c === '>' ? '&gt;' : '&nbsp;';
  });
}
function escapeXML(text, attribute) {
  return text.replace(attribute ? /[&<>"\t\n\r]/g : /[&<>]/g, function (c) {
    return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', '\t': '&#x9;', '\n': '&#xA;', '\r': '&#xD;' }[c];
  });
}

// Into one array of pieces, joined once: no string of the page is built
// piece by piece.
function serialize(node, html) { var out = []; if (html) serializeHTML(node, null, out); else serializeXML(node, null, out); return out.join(''); }
function serializeChildren(node, html) {
  var out = [], kids = node._kids;
  for (var i = 0; i < kids.length; i++) { if (html) serializeHTML(kids[i], node, out); else serializeXML(kids[i], node.namespaceURI, out); }
  return out.join('');
}

function serializeHTML(node, parent, out) {
  switch (node.nodeType) {
    case ELEMENT_NODE: {
      var name = node.qualifiedName, list = node._attributes;
      out.push('<', name);
      for (var i = 0; i < list.length; i++) out.push(' ', list[i].name, '="', escapeAttribute(list[i].value), '"');
      out.push('>');
      if (node.namespaceURI === HTML_NS && VOID[node.localName]) return;
      var kids = node._kids;
      for (var j = 0; j < kids.length; j++) serializeHTML(kids[j], node, out);
      out.push('</', name, '>');
      return;
    }
    case TEXT_NODE:
    case CDATA_SECTION_NODE:
      out.push(parent && parent.nodeType === ELEMENT_NODE && parent.namespaceURI === HTML_NS && SERIALIZED_RAW[parent.localName]
        ? node.data : escapeText(node.data));
      return;
    case COMMENT_NODE: out.push('<!--', node.data, '-->'); return;
    case PROCESSING_INSTRUCTION_NODE: out.push('<?', node.target, ' ', node.data, '>'); return;
    case DOCUMENT_TYPE_NODE: out.push('<!DOCTYPE ', node.name, '>'); return;
    case DOCUMENT_NODE:
    case DOCUMENT_FRAGMENT_NODE: {
      var all = node._kids;
      for (var n = 0; n < all.length; n++) serializeHTML(all[n], node, out);
    }
  }
}

function serializeXML(node, inherited, out) {
  switch (node.nodeType) {
    case ELEMENT_NODE: {
      var name = node.qualifiedName, list = node._attributes;
      out.push('<', name);
      if (node.namespaceURI !== inherited && !node.prefix && !node.hasAttribute('xmlns')) {
        out.push(' xmlns="', escapeXML(node.namespaceURI || '', true), '"');
      }
      for (var i = 0; i < list.length; i++) out.push(' ', list[i].name, '="', escapeXML(list[i].value, true), '"');
      var kids = node._kids;
      if (!kids.length) {
        if (node.namespaceURI !== HTML_NS) out.push('/>');
        else if (VOID[node.localName]) out.push(' />');
        else out.push('></', name, '>');
        return;
      }
      out.push('>');
      for (var j = 0; j < kids.length; j++) serializeXML(kids[j], node.namespaceURI, out);
      out.push('</', name, '>');
      return;
    }
    case TEXT_NODE: out.push(escapeXML(node.data, false)); return;
    case CDATA_SECTION_NODE: out.push('<![CDATA[', node.data, ']]>'); return;
    case COMMENT_NODE: out.push('<!--', node.data, '-->'); return;
    case PROCESSING_INSTRUCTION_NODE: out.push('<?', node.target, ' ', node.data, '?>'); return;
    case DOCUMENT_TYPE_NODE:
      out.push('<!DOCTYPE ', node.name, node.publicId ? ' PUBLIC "' + node.publicId + '"' : '',
               node.systemId ? (node.publicId ? '' : ' SYSTEM') + ' "' + node.systemId + '"' : '', '>');
      return;
    case DOCUMENT_NODE:
    case DOCUMENT_FRAGMENT_NODE: {
      var all = node._kids;
      for (var n = 0; n < all.length; n++) serializeXML(all[n], inherited, out);
    }
  }
}

// ---- Parsing --------------------------------------------------------------
// A tokenizer close to HTML's, and a tree builder that keeps the parts of
// HTML's insertion modes a page's markup leans on: the implied html, head
// and body, what belongs in the head, void elements, raw text, the end tags
// a start tag implies (p, li, dt and dd, options, headings, table parts and
// the tbody a row implies), foreign SVG and MathML with their case kept, and
// an end tag that closes what is open up to it. Misnested formatting
// elements are closed where they end, not reconstructed. XML documents keep
// case, take a self-closing tag anywhere and imply nothing.

var HEAD_ONLY = words('base basefont bgsound link meta title style script noscript noframes template');
var CLOSES_P = words('address article aside blockquote center details dialog dir div dl fieldset figcaption figure ' +
  'footer form h1 h2 h3 h4 h5 h6 header hgroup hr listing main menu nav ol p plaintext pre search section summary table ul xmp');
var SPECIAL = words('address applet area article aside base basefont bgsound blockquote body br button caption center col ' +
  'colgroup dd details dir div dl dt embed fieldset figcaption figure footer form frame frameset h1 h2 h3 h4 h5 h6 head ' +
  'header hgroup hr html iframe img input keygen li link listing main marquee menu meta nav noembed noframes noscript ' +
  'object ol p param plaintext pre script search section select source style summary table tbody td template textarea ' +
  'tfoot th thead title tr track ul wbr xmp');
var SCOPE = words('applet caption html table td th marquee object template');
var IMPLIED_END = words('dd dt li optgroup option p rb rp rt rtc');
var HEADINGS = words('h1 h2 h3 h4 h5 h6');
var TABLE_SECTIONS = words('tbody thead tfoot');
var SVG_HTML_POINTS = words('foreignObject desc title');
var TABLE_SCOPE = words('table html template');
// The name sets the builder asks of the stack, made once.
var BUTTON_SCOPE = words('applet caption html table td th marquee object template button');
var ONLY = { p: words('p'), li: words('li'), ddt: words('dd dt'), a: words('a'), button: words('button'), nobr: words('nobr'),
             cell: words('td th'), tr: words('tr'), section: words('tbody thead tfoot caption colgroup'), row: words('tr td th') };

function Builder(document, root, html, context) {
  this.document = document;
  this.root = root;
  this.html = html;
  this.stack = [];
  this.headElement = null;
  this.bodyElement = null;
  this.htmlElement = null;
  this.afterHead = false;
  // After </body> a comment goes to the html element, after </html> to the
  // document; anything else still goes into the body.
  this.ended = null;
  // The active formatting elements (b, i, a ...): one closed by another's
  // end tag is opened again, as a copy, before the next text or inline
  // element -- `<b><i>x</b>y</i>` is <b><i>x</i></b><i>y</i>. MARKER keeps
  // a cell's or a caption's own.
  this.formatting = [];
  this.fragment = !!context;
  if (context) {
    this.contextNamespace = context.namespaceURI;
  }
}

Builder.prototype.current = function () { return this.stack.length ? this.stack[this.stack.length - 1] : this.root; };

Builder.prototype.namespaceFor = function (name) {
  var current = this.current();
  var ns = current.nodeType === ELEMENT_NODE ? current.namespaceURI : (this.fragment ? this.contextNamespace : HTML_NS);
  if (!this.html) return null;
  if (ns === SVG_NS && SVG_HTML_POINTS[current.localName]) ns = HTML_NS;
  if (ns === MATH_NS && /^(mi|mo|mn|ms|mtext|annotation-xml)$/.test(current.localName)) ns = HTML_NS;
  if (ns === HTML_NS || ns === undefined || ns === null) {
    var lower = name.toLowerCase();
    if (lower === 'svg') return SVG_NS;
    if (lower === 'math') return MATH_NS;
    return HTML_NS;
  }
  return ns;
};

Builder.prototype.ensureHTML = function () {
  if (this.fragment || !this.html) return;
  if (!this.htmlElement) {
    this.htmlElement = new Element(this.document, 'html', HTML_NS);
    this.root.appendChild(this.htmlElement);
    this.stack = [this.htmlElement];
  }
};
Builder.prototype.ensureHead = function () {
  if (this.fragment || !this.html) return;
  this.ensureHTML();
  if (!this.headElement) {
    this.headElement = new Element(this.document, 'head', HTML_NS);
    this.htmlElement.appendChild(this.headElement);
  }
};
Builder.prototype.ensureBody = function (attributes) {
  if (this.fragment || !this.html) return;
  this.ensureHead();
  if (!this.bodyElement) {
    this.bodyElement = new Element(this.document, 'body', HTML_NS);
    if (attributes) this.bodyElement._attributes = attributes;
    this.htmlElement.appendChild(this.bodyElement);
    this.stack = [this.htmlElement, this.bodyElement];
  } else if (attributes) {
    mergeAttributes(this.bodyElement, attributes);
  }
};

// The first of each name, lowercased for an HTML element.
// In place: lowercased for an HTML element, the first of each name kept.
function normalized(list, lower) {
  if (!list.length) return NO_ATTRIBUTES;
  for (var i = 0; i < list.length; i++) {
    if (lower) {
      var name = list[i].name, folded = name.toLowerCase();
      if (folded !== name) list[i].name = intern(folded);
    }
    for (var j = 0; j < i; j++) {
      if (list[j].name === list[i].name) { list.splice(i, 1); i--; break; }
    }
  }
  return list;
}

function mergeAttributes(element, attributes) {
  attributes.forEach(function (a) {
    if (element.hasAttribute(a.name)) return;
    if (element._attributes === NO_ATTRIBUTES) element._attributes = [];
    element._attributes.push(a);
  });
}

Builder.prototype.insertText = function (text) {
  if (!text) return;
  if (!/^[\t\n\f\r ]*$/.test(text)) this.ended = null;
  if (this.html && !this.fragment && !this.bodyElement) {
    // Spaces before the body stay where they are (in the head, or nowhere
    // before it); anything else opens the body.
    var lead = /^[\t\n\f\r ]*/.exec(text)[0];
    if (lead) {
      if (this.headElement && !this.afterHead && this.inHead()) this.appendText(this.current(), lead);
      else if (this.headElement && this.afterHead) this.appendText(this.htmlElement, lead);
      text = text.slice(lead.length);
      if (!text) return;
    }
    this.ensureBody();
  }
  if (this.html && !/^[\t\n\f\r ]*$/.test(text)) this.reconstruct();
  this.appendText(this.current(), text);
};
Builder.prototype.inHead = function () { return this.stack.indexOf(this.headElement) >= 0; };
Builder.prototype.appendText = function (parent, text) {
  var last = parent.lastChild;
  if (last && last.nodeType === TEXT_NODE) last.data += text;
  else parent.appendChild(new Text(this.document, text));
};

Builder.prototype.insertComment = function (data) {
  var parent = this.current();
  if (this.html && !this.fragment && (!this.htmlElement || this.ended === 'html')) parent = this.root;
  else if (this.html && !this.fragment && this.ended === 'body') parent = this.htmlElement;
  parent.appendChild(new Comment(this.document, data));
};

Builder.prototype.popUntil = function (test) {
  while (this.stack.length) {
    var node = this.stack.pop();
    if (test(node)) return node;
  }
  return null;
};

// The innermost open element named `name` (HTML), unless a scope boundary
// comes first; -1 when there is none in scope.
Builder.prototype.inScope = function (names, boundaries) {
  for (var i = this.stack.length - 1; i >= 0; i--) {
    var node = this.stack[i];
    if (node.namespaceURI === HTML_NS && names[node.localName]) return i;
    if (node.namespaceURI !== HTML_NS || (boundaries || SCOPE)[node.localName]) return -1;
  }
  return -1;
};
Builder.prototype.closeTo = function (index) {
  if (index < 0) return;
  for (var i = this.stack.length - 1; i >= index; i--) {
    var node = this.stack[i];
    if (node.namespaceURI === HTML_NS && FORMATTING_SCOPE[node.localName]) this.clearToMarker();
  }
  this.stack.length = index;
};

var FORMATTING = words('a b big code em font i nobr s small strike strong tt u');
var FORMATTING_SCOPE = words('applet caption marquee object td th template');
var MARKER = {};

Builder.prototype.clearToMarker = function () {
  while (this.formatting.length) { if (this.formatting.pop() === MARKER) return; }
};
// Opens again, as copies, the active formatting elements an end tag closed.
Builder.prototype.reconstruct = function () {
  var list = this.formatting;
  if (!list.length) return;
  var at = list.length - 1;
  if (list[at] === MARKER || this.stack.indexOf(list[at]) >= 0) return;
  while (at > 0 && list[at - 1] !== MARKER && this.stack.indexOf(list[at - 1]) < 0) at--;
  for (; at < list.length; at++) {
    var copy = new Element(this.document, list[at].localName, HTML_NS);
    copy._attributes = list[at]._attributes.map(function (a) { return { name: a.name, value: a.value }; });
    this.current().appendChild(copy);
    this.stack.push(copy);
    list[at] = copy;
  }
};

Builder.prototype.closeP = function () {
  var at = this.inScope(ONLY.p, BUTTON_SCOPE);
  if (at >= 0) this.closeTo(at);
};

Builder.prototype.startTag = function (name, attributes, selfClosing) {
  if (!this.html) {
    var parent = this.current();
    var element = new Element(this.document, name, attributes.xmlns !== null ? attributes.xmlns
                                                   : parent.nodeType === ELEMENT_NODE ? parent.namespaceURI : null);
    element._attributes = normalized(attributes.list, false);
    this.current().appendChild(element);
    if (!selfClosing) this.stack.push(element);
    return element;
  }
  var lower = name.toLowerCase();
  var namespace = this.namespaceFor(name);
  attributes.list = normalized(attributes.list, namespace === HTML_NS);
  if (namespace === HTML_NS) {
    name = lower;
    if (!this.fragment) {
      if (name === 'html') { this.ensureHTML(); mergeAttributes(this.htmlElement, attributes.list); return null; }
      if (!this.bodyElement) {
        if (name === 'head') {
          this.ensureHTML();
          if (!this.headElement) {
            this.headElement = new Element(this.document, 'head', HTML_NS);
            this.headElement._attributes = attributes.list;
            this.htmlElement.appendChild(this.headElement);
            this.stack = [this.htmlElement, this.headElement];
          }
          return null;
        }
        if (name === 'body' || name === 'frameset') { this.ensureBody(attributes.list); return null; }
        if (HEAD_ONLY[name]) {
          this.ensureHead();
          var target = this.headElement;
          var head = new Element(this.document, name, HTML_NS);
          head._attributes = attributes.list;
          target.appendChild(head);
          if (!VOID[name]) this.stack = [this.htmlElement, target, head];
          return head;
        }
        this.ensureBody();
      } else if (name === 'body') {
        mergeAttributes(this.bodyElement, attributes.list);
        return null;
      } else if (name === 'head') {
        return null;
      }
    }
    this.impliedEnds(name);
  } else if (!this.fragment && !this.bodyElement) {
    this.ensureBody();
    if (lower === 'svg' || lower === 'math') this.closeP();
  }
  if (namespace === HTML_NS && (!SPECIAL[name] || /^(br|img|input|embed|area|wbr|keygen|applet|marquee|object|select|textarea|button)$/.test(name))) {
    this.reconstruct();
  }
  this.ended = null;
  var element = new Element(this.document, name, namespace, null, attributes.list);
  this.current().appendChild(element);
  if (namespace === HTML_NS ? !VOID[name] : !selfClosing) this.stack.push(element);
  if (namespace === HTML_NS && FORMATTING[name]) this.formatting.push(element);
  if (namespace === HTML_NS && FORMATTING_SCOPE[name]) this.formatting.push(MARKER);
  return element;
};

// What a start tag closes first, and the tbody and tr a table row or cell implies.
Builder.prototype.impliedEnds = function (name) {
  var current = this.current();
  var currentName = current.nodeType === ELEMENT_NODE && current.namespaceURI === HTML_NS ? current.localName : '';
  if (CLOSES_P[name] || name === 'li' || name === 'dd' || name === 'dt') this.closeP();
  if (HEADINGS[name] && HEADINGS[this.current().localName]) this.stack.pop();
  if (name === 'li' || name === 'dd' || name === 'dt') {
    var stops = name === 'li' ? ONLY.li : ONLY.ddt;
    for (var i = this.stack.length - 1; i >= 0; i--) {
      var node = this.stack[i];
      if (node.namespaceURI === HTML_NS && stops[node.localName]) { this.closeTo(i); break; }
      if (node.namespaceURI !== HTML_NS || (SPECIAL[node.localName] && !/^(address|div|p)$/.test(node.localName))) break;
    }
  }
  if (name === 'option' && this.current().localName === 'option') this.stack.pop();
  if (name === 'optgroup') {
    if (this.current().localName === 'option') this.stack.pop();
    if (this.current().localName === 'optgroup') this.stack.pop();
  }
  if (name === 'a') {
    for (var fa = this.formatting.length - 1; fa >= 0 && this.formatting[fa] !== MARKER; fa--) {
      if (this.formatting[fa].localName === 'a') {
        var openA = this.stack.indexOf(this.formatting[fa]);
        this.formatting.splice(fa, 1);
        if (openA >= 0) this.closeTo(openA);
        break;
      }
    }
  }
  if (name === 'button') { var b = this.inScope(ONLY.button); if (b >= 0) this.closeTo(b); }
  if (name === 'nobr') { var n = this.inScope(ONLY.nobr); if (n >= 0) this.closeTo(n); }
  if (name === 'td' || name === 'th') {
    var cell = this.inScope(ONLY.cell, TABLE_SCOPE);
    if (cell >= 0) this.closeTo(cell);
    currentName = this.current().localName;
    if (currentName === 'table' || TABLE_SECTIONS[currentName]) {
      if (currentName === 'table') this.push('tbody');
      this.push('tr');
    }
  } else if (name === 'tr') {
    var row = this.inScope(ONLY.tr, TABLE_SCOPE);
    if (row >= 0) this.closeTo(row);
    else { var openCell = this.inScope(ONLY.cell, TABLE_SCOPE); if (openCell >= 0) this.closeTo(openCell); }
    if (this.current().localName === 'table') this.push('tbody');
  } else if (TABLE_SECTIONS[name] || name === 'caption' || name === 'colgroup') {
    var section = this.inScope(ONLY.section, TABLE_SCOPE);
    if (section < 0) section = this.inScope(ONLY.row, TABLE_SCOPE);
    if (section >= 0) this.closeTo(section);
  } else if (name === 'col' && this.current().localName === 'table') {
    this.push('colgroup');
  }
};
Builder.prototype.push = function (name) {
  var element = new Element(this.document, name, HTML_NS);
  this.current().appendChild(element);
  this.stack.push(element);
};

Builder.prototype.endTag = function (name) {
  var stack = this.stack;
  if (!this.html) {
    for (var x = stack.length - 1; x >= 0; x--) if (stack[x].qualifiedName === name) { this.closeTo(x); return; }
    return;
  }
  var lower = name.toLowerCase();
  if (!this.fragment) {
    if (lower === 'head') { if (this.headElement && this.inHead()) { this.stack = [this.htmlElement]; this.afterHead = true; } return; }
    if (lower === 'body' || lower === 'html') { if (this.bodyElement && this.ended !== 'html') this.ended = lower; return; }
    if (lower === 'br') { this.startTag('br', { list: [] }, false); return; }
    if (lower === 'p' && this.inScope(ONLY.p, BUTTON_SCOPE) < 0) {
      this.ensureBody();
      this.startTag('p', { list: [] }, false);
    }
  }
  if (FORMATTING[lower]) {
    for (var f = this.formatting.length - 1; f >= 0 && this.formatting[f] !== MARKER; f--) {
      if (this.formatting[f].localName === lower) {
        var open = stack.indexOf(this.formatting[f]);
        this.formatting.splice(f, 1);
        if (open >= 0) this.closeTo(open);
        return;
      }
    }
  }
  for (var i = stack.length - 1; i >= 0; i--) {
    var node = stack[i];
    var same = node.namespaceURI === HTML_NS ? node.localName === lower : node.localName.toLowerCase() === lower;
    if (same) { this.closeTo(i); return; }
    if (node.namespaceURI === HTML_NS && SPECIAL[node.localName] && !(SPECIAL[lower] && !SCOPE[node.localName])) return;
  }
};

// By character code, never by one-character strings: a page of CJK text
// would make one per character.
function isSpace(c) { return c === 9 || c === 10 || c === 12 || c === 13 || c === 32; }

// What readAttributes says, in one object it fills each time.
var TAG_END = { at: 0, selfClosing: false };
function tagEnd(at, selfClosing) { TAG_END.at = at; TAG_END.selfClosing = selfClosing; return TAG_END; }

function readAttributes(source, at, html, attributes) {
  var length = source.length;
  while (at < length) {
    var c = source.charCodeAt(at);
    while (at < length && (isSpace(c) || c === 47)) {
      if (c === 47 && source.charCodeAt(at + 1) === 62) return tagEnd(at + 2, true);
      c = source.charCodeAt(++at);
    }
    if (at >= length) break;
    if (c === 62) return tagEnd(at + 1, false);
    var start = at;
    at++;
    while (at < length) { c = source.charCodeAt(at); if (isSpace(c) || c === 47 || c === 62 || c === 61) break; at++; }
    // As written: an HTML element's names are lowercased when it is made,
    // a foreign one's keep their case (viewBox).
    var name = intern(source.slice(start, at));
    while (at < length && isSpace(source.charCodeAt(at))) at++;
    var value = '';
    if (source.charCodeAt(at) === 61) {
      at++;
      while (at < length && isSpace(source.charCodeAt(at))) at++;
      var quote = source.charCodeAt(at);
      if (quote === 34 || quote === 39) {
        var end = source.indexOf(quote === 34 ? '"' : "'", at + 1);
        if (end < 0) end = length;
        value = source.slice(at + 1, end);
        at = end + 1;
      } else {
        var vstart = at;
        while (at < length) { c = source.charCodeAt(at); if (isSpace(c) || c === 62) break; at++; }
        value = source.slice(vstart, at);
      }
      value = decode(value, true, !html);
      if (value.length <= 32) value = intern(value);
    }
    if (!html && name === 'xmlns') attributes.xmlns = value;
    if (attributes.list === NO_ATTRIBUTES) attributes.list = [];
    attributes.list.push({ name: name, value: value });
  }
  return tagEnd(length, false);
}

var CLOSERS = Object.create(null);
// One string for each tag name, attribute name and short attribute value a
// page repeats ("div", "class", "card"), not one per occurrence.
var INTERNED = Object.create(null), internedCount = 0;
function intern(text) {
  var known = INTERNED[text];
  if (known !== undefined) return known;
  if (internedCount < 4096) { INTERNED[text] = text; internedCount++; }
  return text;
}
function isLetter(c) { return (c >= 65 && c <= 90) || (c >= 97 && c <= 122); }
// The end of a tag name starting at `at` (a letter), by character code.
function nameEnd(source, at) {
  var length = source.length;
  while (at < length) { var c = source.charCodeAt(at); if (isSpace(c) || c === 47 || c === 62) break; at++; }
  return at;
}

function parse(source, builder) {
  var html = builder.html, at = 0, length = source.length, text = '';
  function flush() {
    if (text) { builder.insertText(decode(text, false, !html)); text = ''; }
  }
  while (at < length) {
    var lt = source.indexOf('<', at);
    if (lt < 0) { text += source.slice(at); break; }
    text += source.slice(at, lt);
    at = lt;
    var next = source[at + 1];
    if (next === '!') {
      if (source.startsWith('<!--', at)) {
        flush();
        var close = source.indexOf('-->', at + 4);
        var data;
        if (source.startsWith('<!-->', at)) { data = ''; at += 5; }
        else if (source.startsWith('<!--->', at)) { data = ''; at += 6; }
        else if (close < 0) { data = source.slice(at + 4); at = length; }
        else { data = source.slice(at + 4, close); at = close + 3; }
        builder.insertComment(data);
        continue;
      }
      if (/^<!doctype/i.test(source.slice(at, at + 9))) {
        flush();
        var gt = source.indexOf('>', at);
        if (gt < 0) gt = length;
        var inner = source.slice(at + 9, gt).trim();
        var parts = /^(\S*)(?:\s+(?:PUBLIC\s+["']([^"']*)["'](?:\s+["']([^"']*)["'])?|SYSTEM\s+["']([^"']*)["']))?/i.exec(inner) || [];
        if (!builder.fragment && !builder.htmlElement && builder.root.nodeType === DOCUMENT_NODE && !builder.root.doctype) {
          builder.root.appendChild(new DocumentType(builder.document, html ? (parts[1] || 'html').toLowerCase() : (parts[1] || ''),
                                                     parts[2] || '', parts[3] || parts[4] || ''));
        }
        at = gt + 1;
        continue;
      }
      if (source.startsWith('<![CDATA[', at)) {
        var foreign = !html || (builder.current().nodeType === ELEMENT_NODE && builder.current().namespaceURI !== HTML_NS);
        var cdataEnd = source.indexOf(']]>', at + 9);
        if (cdataEnd < 0) cdataEnd = length;
        if (foreign) {
          flush();
          if (html) builder.insertText(source.slice(at + 9, cdataEnd));
          else builder.current().appendChild(new CDATASection(builder.document, source.slice(at + 9, cdataEnd)));
          at = cdataEnd + 3;
          continue;
        }
      }
      flush();
      var bogus = source.indexOf('>', at);
      if (bogus < 0) bogus = length;
      builder.insertComment(source.slice(at + 2, bogus));
      at = bogus + 1;
      continue;
    }
    if (next === '?') {
      flush();
      var piEnd = html ? source.indexOf('>', at) : source.indexOf('?>', at);
      if (piEnd < 0) piEnd = length;
      if (html) builder.insertComment(source.slice(at + 1, piEnd));
      at = piEnd + (html ? 1 : 2);
      continue;
    }
    if (next === '/') {
      if (isLetter(source.charCodeAt(at + 2))) {
        flush();
        var endName = intern(source.slice(at + 2, nameEnd(source, at + 2)));
        var endGt = source.indexOf('>', at);
        at = endGt < 0 ? length : endGt + 1;
        builder.endTag(endName);
        continue;
      }
      if (source[at + 2] === '>') { at += 3; continue; }
      flush();
      var bogusEnd = source.indexOf('>', at);
      if (bogusEnd < 0) bogusEnd = length;
      builder.insertComment(source.slice(at + 2, bogusEnd));
      at = bogusEnd + 1;
      continue;
    }
    if (!isLetter(source.charCodeAt(at + 1))) { text += '<'; at++; continue; }
    flush();
    var startEnd = nameEnd(source, at + 1);
    var startName = intern(source.slice(at + 1, startEnd));
    var attributes = { list: NO_ATTRIBUTES, xmlns: null };
    var tagEnd = readAttributes(source, startEnd, html, attributes);
    at = tagEnd.at;
    var element = builder.startTag(startName, attributes, tagEnd.selfClosing);
    if (html && element && element.namespaceURI === HTML_NS) {
      var name = element.localName;
      var raw = RAW_TEXT[name], escapable = name === 'textarea' || name === 'title';
      if (name === 'plaintext') {
        builder.appendText(element, source.slice(at));
        at = length;
      } else if (raw || escapable) {
        var closer = CLOSERS[name] || (CLOSERS[name] = new RegExp('</' + name + '(?=[\\t\\n\\f\\r />])', 'ig'));
        closer.lastIndex = at;
        var found = closer.exec(source);
        var end = found ? found.index : length;
        var content = source.slice(at, end);
        if (name === 'textarea' && content[0] === '\n') content = content.slice(1);
        if (content) builder.appendText(element, escapable ? decode(content, false, false) : content);
        at = end;
        if (found) {
          var after = source.indexOf('>', end);
          at = after < 0 ? length : after + 1;
          builder.endTag(name);
        }
      } else if (name === 'pre' || name === 'listing') {
        if (source[at] === '\n') at++;
      }
    }
  }
  flush();
}

function parseDocument(source, html, contentType) {
  var document = new Document(html, contentType);
  var builder = new Builder(document, document, html, null);
  parse(source, builder);
  if (html) builder.ensureBody();
  clock++;
  return document;
}

function parseFragment(context, source) {
  var document = context.ownerDocument;
  var html = document._html;
  var fragment = new DocumentFragment(document);
  if (html && context.namespaceURI === HTML_NS && (RAW_TEXT[context.localName] || context.localName === 'textarea' || context.localName === 'title')) {
    if (source) fragment.appendChild(new Text(document, context.localName === 'textarea' || context.localName === 'title' ? decode(source, false, false) : source));
    return fragment;
  }
  var builder = new Builder(document, fragment, html, context);
  if (html && context.namespaceURI === HTML_NS) {
    // The table parts a context implies, so `<tr>` in a tbody's innerHTML stays a row.
    var name = context.localName;
    if (name === 'table' || TABLE_SECTIONS[name] || name === 'tr') {
      var holder = new Element(document, name, HTML_NS);
      fragment.appendChild(holder);
      builder.stack = [holder];
      parse(source, builder);
      var kids = holder._kids.slice();
      detach(holder);
      kids.forEach(function (kid) { fragment.appendChild(kid); });
      return fragment;
    }
  }
  parse(source, builder);
  return fragment;
}

// ---- Selectors ------------------------------------------------------------
// Selectors Level 4 as querySelector takes them: type and universal, #id,
// .class, attributes with every operator and the i and s flags, the four
// combinators, and the pseudo-classes a static document can answer -- the
// structural ones (nth-* with `of S`, first-, last-, only-, empty, root),
// :not, :is, :where, :has, :scope, :link, :checked, :disabled and :enabled,
// :required and :optional. A pseudo-element matches nothing; anything else
// is a SyntaxError, as it is in a browser.

var compiled = Object.create(null), compiledCount = 0;

function compile(selectors) {
  var text = String(selectors);
  if (compiled[text]) return compiled[text];
  var parser = new SelectorParser(text);
  var groups = parser.list(false);
  parser.space();
  if (parser.at < text.length || !groups.length) throw parser.error();
  if (compiledCount > 256) { compiled = Object.create(null); compiledCount = 0; }
  compiled[text] = groups;
  compiledCount++;
  return groups;
}

function SelectorParser(text) { this.text = text; this.at = 0; }
SelectorParser.prototype.error = function () {
  return domError('SyntaxError', "'" + this.text + "' is not a valid selector.");
};
SelectorParser.prototype.space = function () {
  var start = this.at;
  while (this.at < this.text.length) {
    if (/[\t\n\f\r ]/.test(this.text[this.at])) this.at++;
    else if (this.text.startsWith('/*', this.at)) {
      var end = this.text.indexOf('*/', this.at + 2);
      this.at = end < 0 ? this.text.length : end + 2;
    } else break;
  }
  return this.at > start;
};
SelectorParser.prototype.peek = function () { return this.text[this.at]; };

// An identifier, with CSS escapes; null when none starts here.
SelectorParser.prototype.ident = function () {
  var text = this.text, at = this.at, out = '';
  if (text[at] === '-') { out += '-'; at++; if (text[at] === '-') { out += '-'; at++; } }
  var first = true;
  while (at < text.length) {
    var c = text[at];
    if (c === '\\') {
      var hex = /^[0-9a-fA-F]{1,6}[\t\n\f\r ]?/.exec(text.slice(at + 1, at + 8));
      if (hex) {
        var code = parseInt(hex[0], 16);
        out += code === 0 || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF) ? '�' : String.fromCodePoint(code);
        at += 1 + hex[0].length;
      } else if (at + 1 < text.length) { out += text[at + 1]; at += 2; } else break;
    } else if (/[A-Za-z_\u0080-￿]/.test(c) || (!first && /[0-9-]/.test(c)) || (first && out.length && /[0-9-]/.test(c) && false)) {
      out += c; at++;
    } else if (!first && /[0-9-]/.test(c)) { out += c; at++; }
    else break;
    first = false;
  }
  if (out === '' || out === '-' || out === '--' && first) { return null; }
  if (/^-?[0-9]/.test(text.slice(this.at, at))) return null;
  this.at = at;
  return out;
};
SelectorParser.prototype.string = function () {
  var quote = this.text[this.at], out = '';
  this.at++;
  while (this.at < this.text.length && this.text[this.at] !== quote) {
    var c = this.text[this.at];
    if (c === '\\') {
      var hex = /^[0-9a-fA-F]{1,6}[\t\n\f\r ]?/.exec(this.text.slice(this.at + 1, this.at + 8));
      if (hex) { out += String.fromCodePoint(parseInt(hex[0], 16) || 0xFFFD); this.at += 1 + hex[0].length; }
      else if (this.text[this.at + 1] === '\n') this.at += 2;
      else { out += this.text[this.at + 1] || ''; this.at += 2; }
    } else { out += c; this.at++; }
  }
  if (this.text[this.at] !== quote) throw this.error();
  this.at++;
  return out;
};

// A selector list; `relative` allows a leading combinator (:has).
SelectorParser.prototype.list = function (relative) {
  var groups = [];
  do {
    this.space();
    groups.push(this.complex(relative));
    this.space();
  } while (this.text[this.at] === ',' && ++this.at);
  return groups;
};

// A complex selector, its compounds right to left: [{compound, combinator}],
// combinator being how this compound relates to the one before it.
SelectorParser.prototype.complex = function (relative) {
  var parts = [], combinator = ' ';
  this.space();
  if (relative && /[>+~]/.test(this.peek())) { combinator = this.text[this.at++]; this.space(); }
  else if (relative) combinator = ' ';
  var leading = relative ? combinator : null;
  for (;;) {
    var compound = this.compound();
    if (!compound) throw this.error();
    parts.push({ compound: compound, combinator: parts.length ? combinator : leading });
    var spaced = this.space();
    var c = this.peek();
    if (c === '>' || c === '+' || c === '~') { combinator = c; this.at++; this.space(); continue; }
    if (c === undefined || c === ',' || c === ')') break;
    if (spaced) { combinator = ' '; continue; }
    throw this.error();
  }
  return parts.reverse();
};

SelectorParser.prototype.compound = function () {
  var tests = [], start = this.at;
  var c = this.peek();
  if (c === '*') { this.at++; if (this.peek() === '|') { this.at++; this.typeOrStar(tests); } }
  else if (c === '|') { this.at++; this.typeOrStar(tests); }
  else {
    var name = this.ident();
    if (name !== null) {
      if (this.peek() === '|' && this.text[this.at + 1] !== '=') { this.at++; this.typeOrStar(tests); }
      else tests.push({ type: 'tag', name: name });
    }
  }
  for (;;) {
    c = this.peek();
    if (c === '#') {
      this.at++;
      var id = this.identOrHash();
      if (id === null) throw this.error();
      tests.push({ type: 'id', name: id });
    } else if (c === '.') {
      this.at++;
      var cls = this.ident();
      if (cls === null) throw this.error();
      tests.push({ type: 'class', name: cls });
    } else if (c === '[') {
      this.at++;
      tests.push(this.attribute());
    } else if (c === ':') {
      this.at++;
      if (this.peek() === ':') {
        this.at++;
        var element = this.ident();
        if (element === null) throw this.error();
        if (this.peek() === '(') this.balanced();
        tests.push({ type: 'never' });
      } else tests.push(this.pseudo());
    } else break;
  }
  return this.at > start ? tests : null;
};
SelectorParser.prototype.typeOrStar = function (tests) {
  if (this.peek() === '*') { this.at++; return; }
  var name = this.ident();
  if (name === null) throw this.error();
  tests.push({ type: 'tag', name: name });
};
SelectorParser.prototype.identOrHash = function () {
  var text = this.text, at = this.at, out = '';
  while (at < text.length) {
    var c = text[at];
    if (c === '\\') {
      var saved = this.at; this.at = at;
      var piece = this.ident();
      if (piece === null) { this.at = saved; break; }
      out += piece; at = this.at; this.at = saved;
    } else if (/[A-Za-z0-9_\-\u0080-￿]/.test(c)) { out += c; at++; }
    else break;
  }
  if (!out) return null;
  this.at = at;
  return out;
};
SelectorParser.prototype.balanced = function () {
  var depth = 0;
  do {
    var c = this.text[this.at];
    if (c === undefined) throw this.error();
    if (c === '(') depth++;
    else if (c === ')') depth--;
    else if (c === '"' || c === "'") { this.string(); continue; }
    this.at++;
  } while (depth > 0);
};
SelectorParser.prototype.attribute = function () {
  this.space();
  var name;
  if (this.peek() === '*' && this.text[this.at + 1] === '|') { this.at += 2; name = this.ident(); }
  else {
    name = this.ident();
    if (name !== null && this.peek() === '|' && this.text[this.at + 1] !== '=') { this.at++; name = this.ident(); }
  }
  if (name === null) throw this.error();
  this.space();
  var test = { type: 'attr', name: name, op: null, value: null, insensitive: false };
  var op = /^([~|^$*]?=)/.exec(this.text.slice(this.at));
  if (op) {
    test.op = op[1];
    this.at += op[1].length;
    this.space();
    var c = this.peek();
    if (c === '"' || c === "'") test.value = this.string();
    else {
      var v = this.ident();
      if (v === null) {
        var number = /^[0-9][0-9A-Za-z_-]*/.exec(this.text.slice(this.at));
        if (!number) throw this.error();
        v = number[0]; this.at += v.length;
      }
      test.value = v;
    }
    this.space();
    var flag = /^[iIsS](?=[\t\n\f\r \]])/.exec(this.text.slice(this.at)) || /^[iIsS]$/.exec(this.text.slice(this.at, this.at + 1) + (this.text[this.at + 1] === ']' ? '' : 'x'));
    if (this.text[this.at] && /[iIsS]/.test(this.text[this.at]) && (this.text[this.at + 1] === ']' || /[\t\n\f\r ]/.test(this.text[this.at + 1] || ''))) {
      test.insensitive = /[iI]/.test(this.text[this.at]);
      this.at++;
      this.space();
    }
  }
  if (this.peek() !== ']') throw this.error();
  this.at++;
  return test;
};

SelectorParser.prototype.pseudo = function () {
  var name = this.ident();
  if (name === null) throw this.error();
  name = name.toLowerCase();
  var simple = { 'first-child': 1, 'last-child': 1, 'only-child': 1, 'first-of-type': 1, 'last-of-type': 1, 'only-of-type': 1,
                 empty: 1, root: 1, scope: 1, link: 1, 'any-link': 1, checked: 1, disabled: 1, enabled: 1, required: 1,
                 optional: 1, 'read-only': 1, 'read-write': 1, defined: 1 };
  if (this.peek() !== '(') {
    if (simple[name]) return { type: 'pseudo', name: name };
    if (/^(hover|active|focus|focus-visible|focus-within|visited|target|target-within|current|past|future|playing|paused|fullscreen|placeholder-shown|autofill|indeterminate|valid|invalid|in-range|out-of-range|user-invalid|user-valid|default|modal|popover-open)$/.test(name)) {
      return { type: 'never' };
    }
    if (/^(before|after|first-line|first-letter|selection|placeholder|marker|backdrop)$/.test(name)) return { type: 'never' };
    throw this.error();
  }
  this.at++;
  this.space();
  var test;
  if (/^(not|is|where|matches|-webkit-any|any)$/.test(name)) {
    test = { type: name === 'not' ? 'not' : 'is', groups: this.list(false) };
  } else if (name === 'has') {
    test = { type: 'has', groups: this.list(true) };
  } else if (/^nth-(last-)?(child|of-type)$/.test(name)) {
    var formula = /^(?:(even|odd)|([+-]?\d*)?n(?:[\t\n\f\r ]*([+-])[\t\n\f\r ]*(\d+))?|([+-]?\d+))/i.exec(this.text.slice(this.at));
    if (!formula) throw this.error();
    this.at += formula[0].length;
    var a, b;
    if (formula[1]) { a = 2; b = formula[1].toLowerCase() === 'odd' ? 1 : 0; }
    else if (formula[5] !== undefined) { a = 0; b = parseInt(formula[5], 10); }
    else {
      var coefficient = formula[2];
      a = coefficient === undefined || coefficient === '' || coefficient === '+' ? 1 : coefficient === '-' ? -1 : parseInt(coefficient, 10);
      b = formula[4] ? parseInt(formula[4], 10) * (formula[3] === '-' ? -1 : 1) : 0;
    }
    this.space();
    var of = null;
    if (/child$/.test(name) && /^of[\t\n\f\r ]/i.test(this.text.slice(this.at))) { this.at += 2; of = this.list(false); }
    test = { type: 'nth', last: /last/.test(name), ofType: /of-type$/.test(name), a: a, b: b, of: of };
  } else if (name === 'lang' || name === 'dir') {
    var arg = this.ident() || (this.peek() === '"' || this.peek() === "'" ? this.string() : null);
    if (arg === null) throw this.error();
    test = { type: name, value: arg.toLowerCase() };
  } else if (name === 'host' || name === 'host-context' || name === 'state') {
    this.at--; this.balanced(); return { type: 'never' };
  } else throw this.error();
  this.space();
  if (this.peek() !== ')') throw this.error();
  this.at++;
  return test;
};

function attributeOf(element, name) {
  if (element._isHTML) name = name.toLowerCase();
  var list = element._attributes;
  for (var i = 0; i < list.length; i++) if (list[i].name === name) return list[i].value;
  return null;
}

function matchesSelectors(element, groups, scope) {
  for (var i = 0; i < groups.length; i++) if (matchComplex(element, groups[i], 0, scope)) return true;
  return false;
}

function matchComplex(element, parts, index, scope) {
  if (!matchCompound(element, parts[index].compound, scope)) return false;
  if (index + 1 === parts.length) return true;
  var combinator = parts[index].combinator, node;
  if (combinator === '>') {
    node = element.parentNode;
    return !!node && node.nodeType === ELEMENT_NODE && matchComplex(node, parts, index + 1, scope);
  }
  if (combinator === ' ') {
    for (node = element.parentNode; node && node.nodeType === ELEMENT_NODE; node = node.parentNode) {
      if (matchComplex(node, parts, index + 1, scope)) return true;
    }
    return false;
  }
  if (combinator === '+') {
    node = sibling(element, -1, true);
    return !!node && matchComplex(node, parts, index + 1, scope);
  }
  if (combinator === '~') {
    for (node = sibling(element, -1, true); node; node = sibling(node, -1, true)) {
      if (matchComplex(node, parts, index + 1, scope)) return true;
    }
    return false;
  }
  return false;
}

function matchCompound(element, tests, scope) {
  for (var i = 0; i < tests.length; i++) if (!matchTest(element, tests[i], scope)) return false;
  return true;
}

function nthMatches(a, b, position) {
  if (a === 0) return position === b;
  var n = (position - b) / a;
  return n >= 0 && Math.floor(n) === n;
}

function matchTest(element, test, scope) {
  switch (test.type) {
    case 'tag':
      return element._isHTML ? element.localName === test.name.toLowerCase() : element.localName === test.name;
    case 'id': return attributeOf(element, 'id') === test.name;
    case 'class': return hasToken(attributeOf(element, 'class'), test.name);
    case 'attr': {
      var value = attributeOf(element, test.name);
      if (value === null) return false;
      if (test.op === null) return true;
      var wanted = test.value;
      if (test.insensitive) { value = value.toLowerCase(); wanted = wanted.toLowerCase(); }
      switch (test.op) {
        case '=': return value === wanted;
        case '~=': return wanted !== '' && !/[\t\n\f\r ]/.test(wanted) && value.split(/[\t\n\f\r ]+/).indexOf(wanted) >= 0;
        case '|=': return value === wanted || value.indexOf(wanted + '-') === 0;
        case '^=': return wanted !== '' && value.indexOf(wanted) === 0;
        case '$=': return wanted !== '' && value.length >= wanted.length && value.lastIndexOf(wanted) === value.length - wanted.length;
        case '*=': return wanted !== '' && value.indexOf(wanted) >= 0;
      }
      return false;
    }
    case 'never': return false;
    case 'not': return !matchesSelectors(element, test.groups, scope);
    case 'is': return matchesSelectors(element, test.groups, scope);
    case 'has': {
      for (var g = 0; g < test.groups.length; g++) {
        var parts = test.groups[g], leading = parts[parts.length - 1].combinator;
        var candidates = leading === '+' ? [sibling(element, 1, true)].filter(Boolean)
          : leading === '~' ? (function () { var out = [], n = sibling(element, 1, true); while (n) { out.push(n); n = sibling(n, 1, true); } return out; })()
          : leading === '>' ? element._kids.filter(isElement)
          : descendants(element, function () { return true; });
        var anchored = parts.slice();
        for (var c = 0; c < candidates.length; c++) {
          if (matchRelative(candidates[c], anchored, element)) return true;
        }
      }
      return false;
    }
    case 'nth': {
      if (test.of && !matchesSelectors(element, test.of, scope)) return false;
      // The element's place among its siblings that count, from the start or the end.
      var position = 1, step = test.last ? 1 : -1;
      var kids = element.parentNode ? element.parentNode._kids : [element];
      for (var k = kids.indexOf(element) + step; k >= 0 && k < kids.length; k += step) {
        var other = kids[k];
        if (other.nodeType !== ELEMENT_NODE) continue;
        if (test.ofType && (other.localName !== element.localName || other.namespaceURI !== element.namespaceURI)) continue;
        if (test.of && !matchesSelectors(other, test.of, scope)) continue;
        position++;
      }
      return nthMatches(test.a, test.b, position);
    }
    case 'pseudo':
      switch (test.name) {
        case 'first-child': return sibling(element, -1, true) === null;
        case 'last-child': return sibling(element, 1, true) === null;
        case 'only-child': return sibling(element, -1, true) === null && sibling(element, 1, true) === null;
        case 'first-of-type': return matchTest(element, { type: 'nth', ofType: true, last: false, a: 0, b: 1, of: null }, scope);
        case 'last-of-type': return matchTest(element, { type: 'nth', ofType: true, last: true, a: 0, b: 1, of: null }, scope);
        case 'only-of-type':
          return matchTest(element, { type: 'nth', ofType: true, last: false, a: 0, b: 1, of: null }, scope) &&
                 matchTest(element, { type: 'nth', ofType: true, last: true, a: 0, b: 1, of: null }, scope);
        case 'empty':
          return element._kids.every(function (k) { return k.nodeType !== ELEMENT_NODE && !((k.nodeType === TEXT_NODE || k.nodeType === CDATA_SECTION_NODE) && k.data.length); });
        case 'root': return element.parentNode !== null && element.parentNode.nodeType === DOCUMENT_NODE;
        case 'scope': return scope && scope.nodeType === ELEMENT_NODE ? element === scope : element.parentNode !== null && element.parentNode.nodeType === DOCUMENT_NODE;
        case 'link':
        case 'any-link': return /^(a|area)$/.test(element.localName) && element.hasAttribute('href');
        case 'checked':
          return (element.localName === 'input' && /^(checkbox|radio)$/i.test(element.getAttribute('type') || '') && element.hasAttribute('checked')) ||
                 (element.localName === 'option' && element.hasAttribute('selected'));
        case 'disabled': return /^(button|input|select|textarea|optgroup|option|fieldset)$/.test(element.localName) && element.hasAttribute('disabled');
        case 'enabled': return /^(button|input|select|textarea|optgroup|option|fieldset)$/.test(element.localName) && !element.hasAttribute('disabled');
        case 'required': return /^(input|select|textarea)$/.test(element.localName) && element.hasAttribute('required');
        case 'optional': return /^(input|select|textarea)$/.test(element.localName) && !element.hasAttribute('required');
        case 'read-only': return !(/^(input|textarea)$/.test(element.localName) && !element.hasAttribute('readonly') && !element.hasAttribute('disabled'));
        case 'read-write': return /^(input|textarea)$/.test(element.localName) && !element.hasAttribute('readonly') && !element.hasAttribute('disabled');
        case 'defined': return true;
      }
      return false;
    case 'lang': {
      for (var n = element; n && n.nodeType === ELEMENT_NODE; n = n.parentNode) {
        var lang = attributeOf(n, 'lang');
        if (lang !== null) { lang = lang.toLowerCase(); return lang === test.value || lang.indexOf(test.value + '-') === 0; }
      }
      return false;
    }
    case 'dir': {
      for (var d = element; d && d.nodeType === ELEMENT_NODE; d = d.parentNode) {
        var dir = attributeOf(d, 'dir');
        if (dir === 'ltr' || dir === 'rtl') return dir === test.value;
      }
      return test.value === 'ltr';
    }
  }
  return false;
}

// A relative selector (in :has) from a candidate back to the anchor: the
// leftmost compound's combinator must reach `anchor` itself.
function matchRelative(candidate, parts, anchor) {
  if (!matchCompound(candidate, parts[0].compound, anchor)) return false;
  return relativeRest(candidate, parts, 0, anchor);
}
function relativeRest(element, parts, index, anchor) {
  var combinator = parts[index].combinator;
  if (index + 1 === parts.length) {
    if (combinator === '>') return element.parentNode === anchor;
    if (combinator === '+') return sibling(element, -1, true) === anchor;
    if (combinator === '~') { for (var s = sibling(element, -1, true); s; s = sibling(s, -1, true)) if (s === anchor) return true; return false; }
    for (var p = element.parentNode; p; p = p.parentNode) if (p === anchor) return true;
    return false;
  }
  var next = parts[index + 1].compound, node;
  function tryNode(n) { return matchCompound(n, next, anchor) && relativeRest(n, parts, index + 1, anchor); }
  if (combinator === '>') { node = element.parentNode; return !!node && node.nodeType === ELEMENT_NODE && node !== anchor && tryNode(node); }
  if (combinator === '+') { node = sibling(element, -1, true); return !!node && tryNode(node); }
  if (combinator === '~') { for (node = sibling(element, -1, true); node; node = sibling(node, -1, true)) if (tryNode(node)) return true; return false; }
  for (node = element.parentNode; node && node.nodeType === ELEMENT_NODE && node !== anchor; node = node.parentNode) if (tryNode(node)) return true;
  return false;
}

function select(root, selectors, first) {
  var groups = compile(selectors);
  var scope = root.nodeType === ELEMENT_NODE ? root : null;
  var out = [];
  (function walk(node) {
    var kids = node._kids;
    for (var i = 0; i < kids.length; i++) {
      var kid = kids[i];
      if (kid.nodeType !== ELEMENT_NODE) continue;
      if (matchesSelectors(kid, groups, scope)) { out.push(kid); if (first) return true; }
      if (walk(kid) && first) return true;
    }
    return false;
  })(root);
  return out;
}

// ---- DOMParser, XMLSerializer -------------------------------------------

// A string's length in UTF-8, as the body came.
function utf8Length(text) {
  var bytes = 0;
  for (var i = 0; i < text.length; i++) {
    var c = text.charCodeAt(i);
    if (c < 0x80) bytes += 1;
    else if (c < 0x800) bytes += 2;
    else if (c >= 0xD800 && c <= 0xDBFF && i + 1 < text.length) { bytes += 4; i++; }
    else bytes += 3;
  }
  return bytes;
}

var XML_TYPES = { 'text/xml': true, 'application/xml': true, 'application/xhtml+xml': true, 'image/svg+xml': true };

var Parser = class DOMParser {
  parseFromString(string, type) {
    if (arguments.length < 2) throw new TypeError('DOMParser.parseFromString: 2 arguments required, but only ' + arguments.length + ' present.');
    type = String(type);
    var source = String(string);
    if (sourceLimit !== null && sourceLimit !== undefined) {
      var bytes = utf8Length(source);
      if (bytes > sourceLimit) {
        throw domError('NotSupportedError', 'page too large to parse here: ' + bytes + ' bytes, past the ' + sourceLimit + ' this device parses');
      }
    }
    if (type === 'text/html') return parseDocument(source, true, type);
    if (XML_TYPES[type]) {
      var document = parseDocument(source, false, type);
      var root = document.documentElement;
      if (type === 'image/svg+xml' && root && !root.namespaceURI) root.namespaceURI = SVG_NS;
      if (type === 'application/xhtml+xml' && root && !root.namespaceURI) root.namespaceURI = HTML_NS;
      return document;
    }
    throw new TypeError("The provided value '" + type + "' is not a valid enum value of type SupportedType.");
  }
};

var Serializer = class XMLSerializer {
  serializeToString(node) {
    if (!node || !node.nodeType) throw new TypeError("Argument 1 ('root') to XMLSerializer.serializeToString must be an instance of Node");
    var out = [];
    serializeXML(node, null, out);
    return out.join('');
  }
};

function define(name, value) {
  if (typeof global[name] === 'undefined') {
    Object.defineProperty(global, name, { value: value, writable: true, enumerable: false, configurable: true });
  }
}
define('DOMParser', Parser);
define('XMLSerializer', Serializer);
})
"""##
}
#endif
