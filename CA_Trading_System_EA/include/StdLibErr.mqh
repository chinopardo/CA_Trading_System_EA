//+------------------------------------------------------------------+
//|                                                    StdLibErr.mqh |
//|                             Copyright 2000-2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#ifndef CA_STDLIBERR_MQH
   #define CA_STDLIBERR_MQH
   #ifndef ERR_USER_INVALID_HANDLE
      #define ERR_USER_INVALID_HANDLE                            1
   #endif

   #ifndef ERR_USER_INVALID_BUFF_NUM
      #define ERR_USER_INVALID_BUFF_NUM                          2
   #endif

   #ifndef ERR_USER_ITEM_NOT_FOUND
      #define ERR_USER_ITEM_NOT_FOUND                            3
   #endif

   #ifndef ERR_USER_ARRAY_IS_EMPTY
      #define ERR_USER_ARRAY_IS_EMPTY                            1000
   #endif
  
   // Fallback ErrorDescription(...) for environments missing <stderror.mqh>.
   inline string ErrorDescription(const int err)
   {
     switch(err)
     {
       case 0:   return "OK";
       case 1:   return "No result";
       case 2:   return "Common error";
       case 3:   return "Invalid trade params";
       case 4:   return "Server busy";
       case 6:   return "No connection";
       case 8:   return "Too frequent requests";
       case 64:  return "Account disabled";
       case 133: return "Trade disabled";
       case 134: return "Not enough money";
       case 135: return "Price changed";
       case 136: return "Off quotes";
       case 137: return "Broker busy";
       case 138: return "Requote";
       case 139: return "Order locked";
       case 148: return "Too many requests";
       case 4107:return "Invalid price param";
       default:  return "ERR_" + IntegerToString(err);
     }
   }
   //+------------------------------------------------------------------+
#endif // CA_STDLIBERR_MQH