//+------------------------------------------------------------------+
//|                                             CheckEnvironment.mqh |
//|                                         Copyright 2024, Kurokawa |
//|                                   https://twitter.com/ImKurokawa |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Kurokawa"
#property link      "https://twitter.com/ImKurokawa"
#property version   "1.00"
#include <Generic\HashMap.mqh>

#define ChkCompanyName           0x00000001
#define ChkTerminalName          0x00000002
#define ChkServerNames           0x00000004
#define ChkFileName              0x00000008
#define ChkRealAccountOnly       0x00000010
#define ChkConnection            0x00000020
#define ChkExpertAllowed         0x00000040
#define ChkDllAllowed            0x00000080
#define ChkExclusiveInChart      0x00000100
#define ChkExclusiveInTerminal   0x00000200

string ErrorMsgCompanyName;
string ErrorMsgTerminalName;
string ErrorMsgServerNames;
string ErrorMsgFileName;
string ErrorMsgRealAccountOnly;
string ErrorMsgConnection;
string ErrorMsgExpertAllowed;
string ErrorMsgDllAllowed;
string ErrorMsgExclusiveInChart;
string ErrorMsgExclusiveInTerminal;

void _InitMessages()
{
   string lang = TerminalInfoString(TERMINAL_LANGUAGE);
   if (lang == "Japanese")
   {
      ErrorMsgCompanyName           = "証券会社'%s'のサーバーにログインする必要があります。現在ログインしているのは'%s'です。";
      ErrorMsgTerminalName          = "このプログラムはターミナル'%s'上で実行する必要があります。現在のターミナルは'%s'です。";
      ErrorMsgServerNames           = "これらいずれかのサーバーにログインする必要があります:";
      ErrorMsgFileName              = "このプログラムの名前を変更しないでください。配布されたままの状態で実行してください。";
      ErrorMsgRealAccountOnly       = "リアルアカウントまたはコンテストアカウントでログインする必要があります。";
      ErrorMsgConnection            = "サーバーに接続する必要があります。";
      ErrorMsgExpertAllowed         = "'アルゴリズム取引'ボタンを押すか、オプションダイアログの'アルゴリズム取引を許可する'にチェックを入れてください。";
      ErrorMsgDllAllowed            = "オプションダイアログの'DLLの使用を許可する'にチェックを入れてください。";
      ErrorMsgExclusiveInChart      = "このプログラムは同一のチャートで1つのみ実行可能です。";
      ErrorMsgExclusiveInTerminal   = "このプログラムはターミナルで1つのみ実行可能です。";
   }
   else
   {
      ErrorMsgCompanyName           = "You should login into the securities company '%s', instead of current '%s'.";
      ErrorMsgTerminalName          = "You should run this program on the terminal '%s', instead of '%s'";
      ErrorMsgServerNames           = "You should login into one of these servers: ";
      ErrorMsgFileName              = "Do not change the program file name. Run as it was distributed.";
      ErrorMsgRealAccountOnly       = "You should login into either real account or contest account.";
      ErrorMsgConnection            = "You should have the terminal connected to the server.";
      ErrorMsgExpertAllowed         = "Press 'Algo Trading' button, or check 'Allow algorithmic trading' on the Option dialog.";
      ErrorMsgDllAllowed            = "Check 'Allow DLL imports' on the Option dialog.";
      ErrorMsgExclusiveInChart      = "You can run only 1 instance of this program in the same chart window.";
      ErrorMsgExclusiveInTerminal   = "You can run only 1 instance of this program in the terminal.";
   }
}

bool _CheckFlag(uint Flag, uint FlagChecked)
{
   return (Flag & FlagChecked) == FlagChecked;
}

bool CheckEnvironment(uint Flag, string CompanyName, string TerminalName, string ServerNames, string FileName)
{
   _InitMessages();
   string ProgramName = MQLInfoString(MQL_PROGRAM_NAME);
   
   //  Check company name
   if (_CheckFlag(Flag, ChkCompanyName) && CompanyName != TerminalInfoString(TERMINAL_COMPANY))
   {
      PrintFormat(StringFormat(ErrorMsgCompanyName, CompanyName, TerminalInfoString(TERMINAL_COMPANY)));
      return false;
   }
   
   //  Check server names
   if (_CheckFlag(Flag, ChkServerNames))
   {
      string names[];
      StringSplit(ServerNames, ',', names);   
      bool found = false;
      for (int i = 0; i < ArraySize(names); i++)
      {
         if (AccountInfoString(ACCOUNT_SERVER) == names[i])
         {
            found = true;
            break;
         }
      }
      if (!found)
      {
         PrintFormat(StringFormat(ErrorMsgServerNames, ServerNames));
         for (int i = 0; i < ArraySize(names); i++)
         {
            PrintFormat("-%s", names[i]);
         }
         return false;
      }
   }
   
   //  Check terminal name
   if (_CheckFlag(Flag, ChkTerminalName) && TerminalName != TerminalInfoString(TERMINAL_NAME))
   {
      PrintFormat(StringFormat(ErrorMsgTerminalName, TerminalName, TerminalInfoString(TERMINAL_NAME)));
      return false;
   }
   
   //  Check binary file name
   if (_CheckFlag(Flag, ChkFileName) && FileName != ProgramName)
   {
      PrintFormat(ErrorMsgFileName);
      return false;
   }
      
   //  Check multiple instances in the chart
   if (_CheckFlag(Flag, ChkExclusiveInChart))
   {
      int n = 0;
      for (int s = 0; s < ChartGetInteger(0, CHART_WINDOWS_TOTAL); s++)
      {
         for (int i = 0; i < ChartIndicatorsTotal(0, s); i++)
         {
            if (ChartIndicatorName(0, s, i) == ProgramName) n++;
            if (n >= 2)
            {
               PrintFormat(ErrorMsgExclusiveInChart);
               return false;
            }
         }
      }
   }
   
   //  Check multiple instances in the terminal
   if (_CheckFlag(Flag, ChkExclusiveInTerminal))
   {
      int n = 0;      
      long c = ChartFirst();
      while (c != -1)
      {
         for (int s = 0; s < ChartGetInteger(0, CHART_WINDOWS_TOTAL); s++)
         {
            for (int i = 0; i < ChartIndicatorsTotal(0, s); i++)
            {
               if (ChartIndicatorName(0, s, i) == ProgramName) n++;
               if (n >= 2)
               {
                  PrintFormat(ErrorMsgExclusiveInTerminal);
                  return false;
               }
            }
         }
         c = ChartNext(c);
      }
      
   }
   
   //  Check algo-trading allowed
   if (_CheckFlag(Flag, ChkExpertAllowed) && !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      PrintFormat(ErrorMsgExpertAllowed);
      return false;
   }
   
   //  Check dll import
   if (_CheckFlag(Flag, ChkDllAllowed) && !TerminalInfoInteger(TERMINAL_DLLS_ALLOWED))
   {
      PrintFormat(ErrorMsgDllAllowed);
      return false;
   }
   
   //  Check connection
   if (_CheckFlag(Flag, ChkConnection) && !TerminalInfoInteger(TERMINAL_CONNECTED))
   {
      PrintFormat(ErrorMsgConnection);
      return false;
   }
   
   //  Check account type
   if (_CheckFlag(Flag, ChkRealAccountOnly) && AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO)
   {
      PrintFormat(ErrorMsgRealAccountOnly);
      return false;
   }
   
   return true;
}
