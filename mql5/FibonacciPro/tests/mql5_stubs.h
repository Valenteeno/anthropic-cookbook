// Minimal MQL5 API surface for a C++ syntax/type check. Signatures follow the MQL5 docs.
#pragma once
#include <string>
#include <vector>
#include <cstddef>
#include <cmath>
typedef std::string string;
typedef unsigned char uchar;
typedef unsigned short ushort;
typedef unsigned int uint;
typedef unsigned long ulong;
typedef int color;
typedef long datetime;
template<class T> struct MQLArr{std::vector<T> v;T& operator[](int i){return v[i];}const T& operator[](int i)const{return v[i];}};
template<class T> int ArraySize(const MQLArr<T>& a){return (int)a.v.size();}
template<class T,size_t N> int ArraySize(const T (&)[N]){return (int)N;}
template<class T> int ArrayResize(MQLArr<T>& a,int n,int reserve=0){a.v.resize(n);return n;}

enum ENUM_TIMEFRAMES{PERIOD_CURRENT=0,PERIOD_M1=1,PERIOD_M2,PERIOD_M3,PERIOD_M4,PERIOD_M5,PERIOD_M6,PERIOD_M10=10,PERIOD_M12=12,PERIOD_M15=15,PERIOD_M20=20,PERIOD_M30=30,
 PERIOD_H1=16385,PERIOD_H2,PERIOD_H3,PERIOD_H4,PERIOD_H6=16390,PERIOD_H8=16392,PERIOD_H12=16396,PERIOD_D1=16408,PERIOD_W1=32769,PERIOD_MN1=49153};
enum ENUM_OBJECT{OBJ_LABEL=100,OBJ_BUTTON,OBJ_EDIT,OBJ_RECTANGLE_LABEL,OBJ_BITMAP_LABEL,OBJ_TREND,OBJ_TEXT};
enum ENUM_OBJECT_PROPERTY_INTEGER{OBJPROP_COLOR,OBJPROP_STYLE,OBJPROP_WIDTH,OBJPROP_BACK,OBJPROP_ZORDER,OBJPROP_SELECTABLE,OBJPROP_SELECTED,OBJPROP_TYPE,OBJPROP_HIDDEN,
 OBJPROP_CORNER,OBJPROP_XDISTANCE,OBJPROP_YDISTANCE,OBJPROP_XSIZE,OBJPROP_YSIZE,OBJPROP_BGCOLOR,OBJPROP_BORDER_COLOR,OBJPROP_BORDER_TYPE,OBJPROP_FONTSIZE,OBJPROP_STATE,
 OBJPROP_ALIGN,OBJPROP_READONLY,OBJPROP_TIMEFRAMES,OBJPROP_RAY_LEFT,OBJPROP_RAY_RIGHT,OBJPROP_ANCHOR};
enum ENUM_OBJECT_PROPERTY_STRING{OBJPROP_TEXT,OBJPROP_TOOLTIP,OBJPROP_FONT,OBJPROP_BMPFILE};
enum ENUM_BASE_CORNER{CORNER_LEFT_UPPER};
enum ENUM_BORDER_TYPE{BORDER_FLAT};
enum ENUM_ALIGN_MODE{ALIGN_LEFT};
enum ENUM_LINE_STYLE{STYLE_SOLID,STYLE_DASH,STYLE_DOT};
enum ENUM_ANCHOR_POINT{ANCHOR_LEFT_UPPER,ANCHOR_LEFT,ANCHOR_LEFT_LOWER,ANCHOR_LOWER,ANCHOR_RIGHT_LOWER,ANCHOR_RIGHT,ANCHOR_RIGHT_UPPER,ANCHOR_UPPER,ANCHOR_CENTER};
enum ENUM_CHART_POSITION{CHART_BEGIN,CHART_CURRENT_POS,CHART_END};
enum ENUM_CHART_PROPERTY_INTEGER{CHART_MOUSE_SCROLL,CHART_EVENT_MOUSE_MOVE,CHART_WIDTH_IN_PIXELS,CHART_HEIGHT_IN_PIXELS,CHART_FIRST_VISIBLE_BAR,CHART_SCALE,CHART_VISIBLE_BARS,
 CHART_COLOR_FOREGROUND,CHART_COLOR_BACKGROUND,CHART_EVENT_MOUSE_WHEEL,CHART_AUTOSCROLL};
enum ENUM_CHART_PROPERTY_DOUBLE{CHART_PRICE_MIN,CHART_PRICE_MAX};
enum ENUM_CHART_EVENT{CHARTEVENT_KEYDOWN,CHARTEVENT_MOUSE_MOVE,CHARTEVENT_OBJECT_CLICK,CHARTEVENT_CLICK,CHARTEVENT_OBJECT_ENDEDIT,CHARTEVENT_CHART_CHANGE,CHARTEVENT_MOUSE_WHEEL,CHARTEVENT_KEYUP=1000};
enum ENUM_INIT_RETCODE{INIT_SUCCEEDED,INIT_FAILED,INIT_PARAMETERS_INCORRECT};
enum ENUM_COLOR_FORMAT{COLOR_FORMAT_ARGB_NORMALIZE};
enum ENUM_CUSTOMIND_PROPERTY_STRING{INDICATOR_SHORTNAME};
enum ENUM_ACCOUNT_INFO_STRING{ACCOUNT_SERVER};
enum ENUM_ACCOUNT_INFO_INTEGER{ACCOUNT_LOGIN};
enum ENUM_TERMINAL_INFO_INTEGER{TERMINAL_KEYSTATE_CONTROL,TERMINAL_KEYSTATE_SHIFT,TERMINAL_KEYSTATE_MENU};
const int OBJ_NO_PERIODS=-1,OBJ_ALL_PERIODS=0x1fffff;
const int INVALID_HANDLE=-1,INT_VALUE=4;
const int FILE_READ=1,FILE_WRITE=2,FILE_BIN=4,FILE_UNICODE=8,FILE_SHARE_READ=16,FILE_REWRITE=32;
const int TIME_DATE=1,TIME_MINUTES=2,TIME_SECONDS=4;
const color clrNONE=-1;
extern string _Symbol;extern int _Digits;extern double _Point;extern int _Period;

struct MqlRates{datetime time;double open,high,low,close;long tick_volume;int spread;long real_volume;};

template<class A,class B> double MathMax(A a,B b){return a>b?a:b;}
template<class A,class B> double MathMin(A a,B b){return a<b?a:b;}
double MathAbs(double v);double MathRound(double v);double MathFloor(double v);double MathMod(double a,double b);
double MathPow(double a,double b);double MathSqrt(double v);bool MathIsValidNumber(double v);void MathSrand(uint seed);int MathRand();
double NormalizeDouble(double v,int digits);
string DoubleToString(double v,int digits=8);string IntegerToString(long v,int len=0,ushort fill=' ');
long StringToInteger(const string& s);double StringToDouble(const string& s);datetime StringToTime(const string& s);
string TimeToString(datetime t,int mode=TIME_DATE|TIME_MINUTES);
int StringLen(const string& s);int StringFind(const string& s,const string& match,int start=0);
string StringSubstr(const string& s,int start,int length=-1);int StringReplace(string& s,const string& find,const string& repl);
ushort StringGetCharacter(const string& s,int pos);bool StringToUpper(string& s);int StringTrimLeft(string& s);int StringTrimRight(string& s);
int StringSplit(const string& s,ushort sep,MQLArr<string>& result);int StringCompare(const string& a,const string& b,bool cs=true);
template<class... T> string StringFormat(const string& f,T... args){return f;}
template<class... T> void Print(T... args){}
ulong GetTickCount64();ulong GetMicrosecondCount();long ChartID();
void ResetLastError();int GetLastError();
uint ColorToARGB(color c,uchar alpha=255);
bool ObjectCreate(long chart,const string& name,ENUM_OBJECT type,int sub,datetime t,double p);
bool ObjectCreate(long chart,const string& name,ENUM_OBJECT type,int sub,datetime t1,double p1,datetime t2,double p2);
bool ObjectMove(long chart,const string& name,int point,datetime t,double p);
bool ChartNavigate(long chart,ENUM_CHART_POSITION pos,int shift=0);
string ShortToString(ushort code);bool StringToLower(string& s);
bool ObjectDelete(long chart,const string& name);int ObjectsDeleteAll(long chart,const string& prefix,int sub=-1,int type=-1);
int ObjectFind(long chart,const string& name);int ObjectsTotal(long chart,int sub=-1,int type=-1);string ObjectName(long chart,int pos,int sub=-1,int type=-1);
bool ObjectSetInteger(long chart,const string& name,ENUM_OBJECT_PROPERTY_INTEGER prop,long value);
bool ObjectSetString(long chart,const string& name,ENUM_OBJECT_PROPERTY_STRING prop,const string& value);
long ObjectGetInteger(long chart,const string& name,ENUM_OBJECT_PROPERTY_INTEGER prop,int mod=0);
string ObjectGetString(long chart,const string& name,ENUM_OBJECT_PROPERTY_STRING prop,int mod=0);
long ChartGetInteger(long chart,ENUM_CHART_PROPERTY_INTEGER prop,int sub=0);bool ChartSetInteger(long chart,ENUM_CHART_PROPERTY_INTEGER prop,long value);
double ChartGetDouble(long chart,ENUM_CHART_PROPERTY_DOUBLE prop,int sub=0);void ChartRedraw(long chart=0);
bool ChartTimePriceToXY(long chart,int sub,datetime t,double p,int& x,int& y);
bool ChartXYToTimePrice(long chart,int x,int y,int& sub,datetime& t,double& p);
bool ChartIndicatorDelete(long chart,int sub,const string& name);
bool IndicatorSetString(ENUM_CUSTOMIND_PROPERTY_STRING prop,const string& value);
bool EventSetMillisecondTimer(int ms);void EventKillTimer();
long TerminalInfoInteger(ENUM_TERMINAL_INFO_INTEGER prop);
string AccountInfoString(ENUM_ACCOUNT_INFO_STRING prop);long AccountInfoInteger(ENUM_ACCOUNT_INFO_INTEGER prop);
int PeriodSeconds(ENUM_TIMEFRAMES tf=PERIOD_CURRENT);
int iBarShift(const string& sym,ENUM_TIMEFRAMES tf,datetime t,bool exact=false);
datetime iTime(const string& sym,ENUM_TIMEFRAMES tf,int shift);double iOpen(const string& sym,ENUM_TIMEFRAMES tf,int shift);
double iHigh(const string& sym,ENUM_TIMEFRAMES tf,int shift);double iLow(const string& sym,ENUM_TIMEFRAMES tf,int shift);double iClose(const string& sym,ENUM_TIMEFRAMES tf,int shift);
int CopyRates(const string& sym,ENUM_TIMEFRAMES tf,int start,int count,MQLArr<MqlRates>& rates);
int FileOpen(const string& name,int flags,short delimiter='\t',uint codepage=0);void FileClose(int h);void FileFlush(int h);
uint FileWriteInteger(int h,int v,int size=INT_VALUE);uint FileWriteLong(int h,long v);uint FileWriteDouble(int h,double v);uint FileWriteString(int h,const string& s,int len=-1);
int FileReadInteger(int h,int size=INT_VALUE);long FileReadLong(int h);double FileReadDouble(int h);string FileReadString(int h,int len=-1);
bool FileIsEnding(int h);ulong FileTell(int h);ulong FileSize(int h);bool FileIsExist(const string& name,int common=0);
bool FileCopy(const string& src,int common,const string& dst,int mode);bool FileMove(const string& src,int common,const string& dst,int mode);
bool FileDelete(const string& name,int common=0);bool FolderCreate(const string& name,int common=0);
long FileFindFirst(const string& filter,string& name,int common=0);bool FileFindNext(long h,string& name);void FileFindClose(long h);
class CCanvas{public:
 bool CreateBitmapLabel(long chart,int sub,const string& name,int x,int y,int w,int h,ENUM_COLOR_FORMAT fmt);
 void Destroy();int Width();int Height();void Erase(uint clr=0);void Update(bool redraw=true);
 void PixelSet(int x,int y,uint clr);void FillRectangle(int x1,int y1,int x2,int y2,uint clr);void Rectangle(int x1,int y1,int x2,int y2,uint clr);
 void Line(int x1,int y1,int x2,int y2,uint clr);bool FontSet(const string& name,int size,uint flags=0,uint angle=0);
 int TextWidth(const string& text);int TextHeight(const string& text);void TextOut(int x,int y,const string& text,uint clr,uint align=0);};
