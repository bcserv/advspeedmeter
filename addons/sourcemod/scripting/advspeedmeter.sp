/*****************************************************************


C O M P I L E   O P T I O N S


*****************************************************************/
// enforce semicolons after each code statement
#pragma semicolon 1

/*****************************************************************


P L U G I N   I N C L U D E S


*****************************************************************/
#include <sourcemod>
#include <sdktools>
#include <smlib>
#include <smlib/pluginmanager>

#undef REQUIRE_PLUGIN
#include <basekeyhintbox>

/*****************************************************************


P L U G I N   I N F O


*****************************************************************/
public Plugin:myinfo = {
	name 						= "Advanced Speed Meter",
	author 						= "Chanz",
	description 				= "Show current player speed, saves/displays speed ranking for round and map",
	version 					= "3.8.17",
	url 						= "https://forums.alliedmods.net/showthread.php?p=1355865"
}

/*****************************************************************


P L U G I N   D E F I N E S


*****************************************************************/
#define MAX_UNIT_TYPES 4
#define MAX_UNITMESS_LENGTH 5

#define STEAMAUTH_LENGTH 32

/*****************************************************************


G L O B A L   V A R S


*****************************************************************/
// Console Variables
new Handle:g_cvarEnable 					= INVALID_HANDLE;
new Handle:g_cvarUnit = INVALID_HANDLE;
new Handle:g_cvarFloodTime = INVALID_HANDLE;
new Handle:g_cvarDisplayTick = INVALID_HANDLE;
new Handle:g_cvarShowSpeedToSpecs = INVALID_HANDLE;

// Console Variables: Runtime Optimizers
new g_iPlugin_Enable 					= 1;
new g_iPlugin_Unit = 0;
new Float:g_fPlugin_FloodTime = 0.0;
new Float:g_fPlugin_DisplayTick = 0.0;
new bool:g_bPlugin_ShowSpeedToSpecs = false;

// Plugin Internal Variables
new bool:g_bFeatureStatus_ShowHudText = false;
new Handle:g_hTimer_Think = INVALID_HANDLE;
new Float:g_fLastCommand = 0.0;

// Library Load Checks
new bool:g_bLib_BaseKeyHintBox = false;

// Game Variables
new bool:g_bRoundEnded = false;
new bool:g_bGameEnded = false;

// Server Variables


// Map Variables


// Client Variables
new Handle:g_hClient_UserId 				= INVALID_HANDLE;
new Handle:g_hClient_SteamId 				= INVALID_HANDLE;
new Handle:g_hClient_Name 					= INVALID_HANDLE;
new Handle:g_hClient_MaxRoundSpeed 			= INVALID_HANDLE;
new Handle:g_hClient_MaxGameSpeed 			= INVALID_HANDLE;

// M i s c
new String:g_szUnitMess_Name[MAX_UNIT_TYPES][MAX_UNITMESS_LENGTH] = {
	
	"km/h",
	"mph",
	"u/s",
	"m/s"
};

new Float:g_fUnitMess_Calc[MAX_UNIT_TYPES] = {
	
	0.04263157894736842105263157894737,
	0.05681807590283512505382617918945,
	1.0,
	0.254
};

/*****************************************************************


F O R W A R D   P U B L I C S


*****************************************************************/
public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max){
	
	return APLRes_Success;
}

public OnPluginStart() {
	
	// Initialization for SMLib
	PluginManager_Initialize("advspeedmeter","[SM] ",true);
	
	// Translations
	// LoadTranslations("common.phrases");
	
	
	// Command Hooks (AddCommandListener) (If the command already exists, like the command kill, then hook it!)
	
	
	// Register New Commands (PluginManager_RegConsoleCmd) (If the command doesn't exist, hook it here)
	PluginManager_RegConsoleCmd("topspeed",Command_TopSpeed,"Shows the fastest player on the map");
	
	// Register Admin Commands (PluginManager_RegAdminCmd)
	PluginManager_RegAdminCmd("sm_listtopspeed",Command_ListTopSpeed,ADMFLAG_ROOT,"dumps all top speed players arrays in the console");
	
	// Cvars: Create a global handle variable.
	g_cvarEnable = PluginManager_CreateConVar("enable","1","Enables or disables this plugin");
	g_cvarUnit = PluginManager_CreateConVar("unit", "0", "Unit of measurement of speed (0=kilometers per hour, 1=miles per hour, 2=units per second, 3=meters per second)", FCVAR_PLUGIN,true,0.0,true,3.0);
	g_cvarDisplayTick = PluginManager_CreateConVar("tick", "0.2", "This sets how often the display is redrawn (this is the display tick rate).",FCVAR_PLUGIN);
	g_cvarShowSpeedToSpecs = PluginManager_CreateConVar("showtospecs", "1.0", "Should spectators be able to see the speed of the one they observe?",FCVAR_PLUGIN,true,0.0,true,1.0);
	//g_cvar_FloodTime will be found in OnConfigsExecuted!
	
	// Hook ConVar Change
	HookConVarChange(g_cvarEnable,ConVarChange_Enable);
	HookConVarChange(g_cvarUnit,ConVarChange_Unit);
	HookConVarChange(g_cvarDisplayTick,ConVarChange_DisplayTick);
	HookConVarChange(g_cvarShowSpeedToSpecs,ConVarChange_SpeedToSpecs);
	//g_cvar_FloodTime is hooked in OnConfigsExecuted!
	
	// Event Hooks
	HookEventEx("round_start",Event_RoundStart);
	HookEventEx("round_end",Event_RoundEnd);
	HookEvent("player_changename", Event_PlayerNameChange);
	
	// Library
	g_bLib_BaseKeyHintBox = LibraryExists("basekeyhintbox");	
	//PrintToServer("###### basekeyhintbox: %d; tgsefjtisdjfz: %d",g_bLib_BaseKeyHintBox,LibraryExists("asgdfujsdft"));
	
	// Features
	if(CanTestFeatures()){
		g_bFeatureStatus_ShowHudText = (GetFeatureStatus(FeatureType_Native,"SetHudTextParams") && GetFeatureStatus(FeatureType_Native,"ShowHudText"));
	}
	
	//PrintToServer("g_bFeatureStatus_ShowHudText: %d",g_bFeatureStatus_ShowHudText);
	
	// Create ADT Arrays
	g_hClient_UserId = CreateArray();
	g_hClient_SteamId = CreateArray(MAX_STEAMAUTH_LENGTH);
	g_hClient_Name = CreateArray(MAX_NAME_LENGTH);
	g_hClient_MaxRoundSpeed = CreateArray();
	g_hClient_MaxGameSpeed = CreateArray();
}

public OnLibraryAdded(const String:name[]){
	
	//PrintToServer("advspeedmeter: added lib '%s'",name);
	
	if(StrEqual(name,"basekeyhintbox",false)){
		
		g_bLib_BaseKeyHintBox = true;
		
		if(g_hTimer_Think != INVALID_HANDLE){
			CloseHandle(g_hTimer_Think);
			g_hTimer_Think = INVALID_HANDLE;
		}
		g_hTimer_Think = CreateTimer(BaseKeyHintBox_GetPrintInterval(), Timer_Think,INVALID_HANDLE,TIMER_REPEAT);
	}
}
public OnLibraryRemoved(const String:name[]){
	
	//PrintToServer("advspeedmeter: removed lib '%s'",name);
	
	if(StrEqual(name,"basekeyhintbox",false)){
		
		g_bLib_BaseKeyHintBox = false;
	}
}

public OnConfigsExecuted(){
	
	// Set your ConVar runtime optimizers here
	g_iPlugin_Enable = GetConVarInt(g_cvarEnable);
	g_iPlugin_Unit = GetConVarInt(g_cvarUnit);
	g_fPlugin_DisplayTick = g_bLib_BaseKeyHintBox ? BaseKeyHintBox_GetPrintInterval() : GetConVarFloat(g_cvarDisplayTick);
	g_bPlugin_ShowSpeedToSpecs = GetConVarBool(g_cvarShowSpeedToSpecs);
	//g_cvar_FloodTime is set in OnConfigsExecuted!
	
	// Kill Timer if its existing and start it
	if(g_hTimer_Think != INVALID_HANDLE){
		CloseHandle(g_hTimer_Think);
		g_hTimer_Think = INVALID_HANDLE;
	}
	g_hTimer_Think = CreateTimer(g_fPlugin_DisplayTick, Timer_Think, INVALID_HANDLE, TIMER_REPEAT);
	
	// SourceMod Flood Time
	g_cvarFloodTime = FindConVar("sm_flood_time");
	if(g_cvarFloodTime == INVALID_HANDLE){
		
		g_fPlugin_FloodTime = 0.75;
	}
	else {
		g_fPlugin_FloodTime = GetConVarFloat(g_cvarFloodTime);
		HookConVarChange(g_cvarFloodTime,ConVarChange_FloodTime);
	}
	
	//Late load init.
	ClientAll_Initialize();
}

public OnMapStart(){
	
	// hax against valvefail (thx psychonic for fix)
	if (GuessSDKVersion() == SOURCE_SDK_EPISODE2VALVE) {
		SetConVarString(Plugin_VersionCvar, Plugin_Version);
	}
	
	g_fLastCommand = GetGameTime();
	
	ClearArray(g_hClient_UserId);
	ClearArray(g_hClient_SteamId);
	ClearArray(g_hClient_Name);
	ClearArray(g_hClient_MaxRoundSpeed);
	ClearArray(g_hClient_MaxGameSpeed);
	
	LOOP_CLIENTS(client,CLIENTFILTER_INGAMEAUTH){
		InsertNewPlayer(client);
	}
	
	g_bGameEnded = false;
	g_bRoundEnded = false;
}

public OnClientPutInServer(client){
	
	Client_Initialize(client);
}

public OnClientPostAdminCheck(client){
	
	Client_Initialize(client);
}


/**************************************************************************************


C A L L B A C K   F U N C T I O N S


**************************************************************************************/
public Action:Timer_Think(Handle:timer){
	
	if(g_iPlugin_Enable != 1){
		return Plugin_Continue;
	}
	
	if(g_bRoundEnded || g_bGameEnded){
		return Plugin_Continue;
	}
	
	LOOP_CLIENTS(client,CLIENTFILTER_INGAMEAUTH){
		ShowSpeedMeter(client);
	}
	
	return Plugin_Continue;
}

/**************************************************************************************

C O N  V A R  C H A N G E

**************************************************************************************/
/* Example Callback Con Var Change*/
public ConVarChange_Enable(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	g_iPlugin_Enable = StringToInt(newVal);
}

public ConVarChange_Unit(Handle:cvar, const String:oldVal[], const String:newVal[]){
	
	g_iPlugin_Unit = StringToInt(newVal);
}

public ConVarChange_DisplayTick(Handle:cvar, const String:oldVal[], const String:newVal[]){
	
	g_fPlugin_DisplayTick = g_bLib_BaseKeyHintBox ? BaseKeyHintBox_GetPrintInterval() : StringToFloat(newVal);
	
	if(g_hTimer_Think != INVALID_HANDLE){
		CloseHandle(g_hTimer_Think);
		g_hTimer_Think = INVALID_HANDLE;
	}
	
	g_hTimer_Think = CreateTimer(g_fPlugin_DisplayTick, Timer_Think, INVALID_HANDLE, TIMER_REPEAT);
}

public ConVarChange_FloodTime(Handle:cvar, const String:oldVal[], const String:newVal[]){
	
	g_fPlugin_FloodTime = StringToFloat(newVal);
}

public ConVarChange_SpeedToSpecs(Handle:cvar, const String:oldVal[], const String:newVal[]){
	
	g_bPlugin_ShowSpeedToSpecs = bool:StringToInt(newVal);
}

/**************************************************************************************

C O M M A N D S

**************************************************************************************/
/* Example Command Callback
public Action:Command_(client, args)
{

return Plugin_Handled;
}
*/
public Action:Command_TopSpeed(client,args){
	
	if(g_fLastCommand > GetGameTime()){
		
		PrintToChat(client,"[SM] %t","Flooding the server");
		return Plugin_Handled;
	}
	g_fLastCommand = GetGameTime() + g_fPlugin_FloodTime;
	
	ShowBestGame();
	
	return Plugin_Handled;
}

public Action:Command_ListTopSpeed(client,args){
	
	new size = GetArraySize(g_hClient_SteamId);
	
	PrintToConsole(client,"array size: %d",size);
	
	if((size != GetArraySize(g_hClient_Name)) || (size != GetArraySize(g_hClient_MaxRoundSpeed)) || (size != GetArraySize(g_hClient_MaxGameSpeed))){
		
		LogError("array size is different from other arrays. Report to %s on %s",Plugin_Author,Plugin_Url);
		return Plugin_Handled;
	}
	
	new String:searchTerm[64];
	if(args > 0){
		GetCmdArg(1,searchTerm,sizeof(searchTerm));
	}
	
	PrintToConsole(client,"Listing Top Speeds:");
	
	new String:auth[STEAMAUTH_LENGTH];
	new String:name[MAX_NAME_LENGTH];
	new Float:gamespeed;
	new Float:roundspeed;
	
	for(new i=0;i<size;i++){
		
		GetArrayString(g_hClient_SteamId,i,auth,sizeof(auth));
		
		GetArrayString(g_hClient_Name,i,name,sizeof(name));
		
		if(args > 0){
			
			if(StrContains(name,searchTerm,false) == -1){
				
				continue;
			}
		}
		
		gamespeed = GetArrayCell(g_hClient_MaxGameSpeed,i);
		roundspeed = GetArrayCell(g_hClient_MaxRoundSpeed,i);
		
		PrintToConsole(client,"#%d; Name: %.64s; SteamID: %.32s; gamespeed: %.4f; roundspeed: %.4f",i,name,auth,gamespeed,roundspeed);
	}
	
	return Plugin_Handled;
}

/**************************************************************************************

E V E N T S

**************************************************************************************/
/* Example Callback Event
public Action:Event_Example(Handle:event, const String:name[], bool:dontBroadcast)
{

}
*/
public Event_RoundStart(Handle:event, const String:name[], bool:broadcast){
	
	SetClientMaxRoundSpeedAll(0.0);
	g_bRoundEnded = false;
	g_bGameEnded = false;
	
}

public Event_RoundEnd(Handle:event, const String:name[], bool:broadcast){
	
	g_bRoundEnded = true;
	
	new timeleft = 0;
	GetMapTimeLeft(timeleft);
	
	if(timeleft <= 0){
		GameEnd();
	}
	else {
		ShowBestRound();
	}
}

public Event_PlayerNameChange(Handle:event, const String:name[], bool:broadcast) {
	
	decl client;
	decl String:oldName[MAX_NAME_LENGTH];
	decl String:newName[MAX_NAME_LENGTH];
	
	client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!Client_IsValid(client) || !IsClientInGame(client)){return;}
	
	GetEventString(event,"newname",newName,sizeof(newName));
	GetEventString(event,"oldname",oldName,sizeof(oldName));
	
	if(!StrEqual(oldName,newName,true)){
		
		decl String:clientAuth[STEAMAUTH_LENGTH];
		GetClientAuthString(client,clientAuth,sizeof(clientAuth));
		
		new id = FindStringInArray(g_hClient_SteamId,clientAuth);
		
		if(id != -1){
			
			SetArrayString(g_hClient_Name,id,newName);
		}
	}
}

/***************************************************************************************


P L U G I N   F U N C T I O N S


***************************************************************************************/



/***************************************************************************************

S T O C K

***************************************************************************************/
stock ShowSpeedMeter(player){
	
	new client = -1;
	new Obs_Mode:observMode = Client_GetObserverMode(player);
	
	if(g_bPlugin_ShowSpeedToSpecs && IsClientObserver(player) && (observMode == OBS_MODE_CHASE || observMode == OBS_MODE_IN_EYE)){
		client = Client_GetObserverTarget(player);
	}
	else if(IsPlayerAlive(player)){
		client = player;
	}
	else {
		return;
	}
	
	if(!Client_IsValid(client) && !IsClientInGame(client) && !IsPlayerAlive(client) && !IsClientAuthorized(client)){
		return;
	}
	
	new Float:clientVel[3];
	Entity_GetAbsVelocity(client,clientVel);
	clientVel[2] = 0.0;
	
	new Float:speed = GetVectorLength(clientVel);
	new Float:maxSpeed = 0.0;
	
	// only walking and what players? seems ( 1 << 16 ) isnt defined but yet used.
	// I with I would remember what it was :S I promise to document such shit better!
	if(GetEntityMoveType(client) == MOVETYPE_WALK && speed != 0.0){
		
		new String:clientAuth[STEAMAUTH_LENGTH];
		GetClientAuthString(client,clientAuth,sizeof(clientAuth));
		
		new clientIndex = FindStringInArray(g_hClient_SteamId,clientAuth);
		
		if(clientIndex == -1){
			LogError("didn't find client with steamid: '%s' in array g_hClientSteamId, Name: %N",clientAuth,client);
			return;
		}
		
		if(GetArrayCell(g_hClient_MaxRoundSpeed,clientIndex) < speed){
			SetArrayCell(g_hClient_MaxRoundSpeed,clientIndex,speed);
		}
		
		if(GetArrayCell(g_hClient_MaxGameSpeed,clientIndex) < speed){
			SetArrayCell(g_hClient_MaxGameSpeed,clientIndex,speed);
		}
		
		maxSpeed = GetArrayCell(g_hClient_MaxGameSpeed,clientIndex);
	}
	
	decl String:output[128];
	Format(output,sizeof(output),
		"%T\n%.1f %s (%.1f %s)",
		"Current speed Max speed",
		player,
		speed*g_fUnitMess_Calc[g_iPlugin_Unit],
		g_szUnitMess_Name[g_iPlugin_Unit],
		maxSpeed*g_fUnitMess_Calc[g_iPlugin_Unit],
		g_szUnitMess_Name[g_iPlugin_Unit]
	);
	
	if(g_bFeatureStatus_ShowHudText) {
		
		SetHudTextParams(0.01, 1.0, g_fPlugin_DisplayTick, 255, 255, 255, 255, 0, 6.0, 0.01, 0.01);
		ShowHudText(player, -1, output);
	}
	else if(g_bLib_BaseKeyHintBox) {
		
		BaseKeyHintBox_PrintToClient(player,g_fPlugin_DisplayTick,output);
	}
	else {
		
		Client_PrintHintText(player,output);
	}
}

stock ShowBestRound()
{
	
	SortBestRound();
	
	new String:clientName[35];
	new size = GetArraySize(g_hClient_Name);
	new String:clientSteamId[STEAMAUTH_LENGTH];
	new String:arraySteamId[STEAMAUTH_LENGTH];
	
	Client_PrintToChatAll(false,"{R}[Adv Speed Meter] {G}%t","The fastest players in this round");
	//PrintToChatAll("{R}[Adv Speed Meter] {G}%t","The fastest players in this round");
	
	for(new i=0;i<size;i++){
		
		GetArrayString(g_hClient_Name,i,clientName,sizeof(clientName));
		GetArrayString(g_hClient_SteamId,i,arraySteamId,sizeof(arraySteamId));
		
		for(new client=1;client<=MaxClients;client++){
			
			if(IsClientInGame(client)){
				
				GetClientAuthString(client,clientSteamId,sizeof(clientSteamId));
				new Float:speed = Float:GetArrayCell(g_hClient_MaxRoundSpeed,i) * g_fUnitMess_Calc[g_iPlugin_Unit];
				
				if(StrEqual(arraySteamId,clientSteamId,false)){
					
					Client_PrintToChat(client,false,"{G}%d{R}. %s ({G}%.1f %s{R})",i+1,clientName,speed,g_szUnitMess_Name[g_iPlugin_Unit]);
					//PrintToChat(client,"{G}%d{R}. %s ({G}%.1f %s{R})",i+1,clientName,speed,g_szUnitMess_Name[g_iPlugin_Unit]);
				}
				else if(i < 3){
					
					Client_PrintToChat(client,false,"{G}%d{R}. {G}%s (%.1f %s)",i+1,clientName,speed,g_szUnitMess_Name[g_iPlugin_Unit]);
					//PrintToChat(client,"{G}%d{R}. {G}%s (%.1f %s)",i+1,clientName,speed,g_szUnitMess_Name[g_iPlugin_Unit]);
				}
			}
		}
	}
	
}

stock GameEnd(){
	
	g_bGameEnded = true;
	
	ShowBestGame();
}

stock ShowBestGame(){
	
	SortBestGame();
	
	new String:clientName[35];
	new size = GetArraySize(g_hClient_Name);
	
	new String:clientSteamId[STEAMAUTH_LENGTH];
	new String:arraySteamId[STEAMAUTH_LENGTH];
	new Float:speed = -1.0;
	
	Client_PrintToChatAll(false,"{R}[Adv Speed Meter] {G}%t","The fastest players on this map");
	//PrintToChatAll("{R}[Adv Speed Meter] {G}%t","The fastest players on this map");
	
	for(new i=0;i<size;i++){
		
		GetArrayString(g_hClient_Name,i,clientName,sizeof(clientName));
		GetArrayString(g_hClient_SteamId,i,arraySteamId,sizeof(arraySteamId));
		
		LOOP_CLIENTS(client,CLIENTFILTER_INGAMEAUTH){
			
			if(IsFakeClient(client)){
				Format(clientSteamId,sizeof(clientSteamId),"BOT_%N",client);
			}
			else {
				GetClientAuthString(client,clientSteamId,sizeof(clientSteamId));
			}
			speed = Float:GetArrayCell(g_hClient_MaxGameSpeed,i) * g_fUnitMess_Calc[g_iPlugin_Unit];
			
			//PrintToConsole(client,"clientMaxSpeedInUnits: %f; multiplier: %f; speed: %f",GetArrayCell(g_hClient_MaxGameSpeed,i),g_fUnitMess_Calc[g_iPlugin_Unit],speed);
			
			if(StrEqual(arraySteamId,clientSteamId,false)){
				
				Client_PrintToChat(client,false,"{G}%d{R}. %s ({G}%.1f %s{R}) %N",i+1,clientName,speed,g_szUnitMess_Name[g_iPlugin_Unit],client);
				//PrintToChat(client,"{G}%d{R}. %s ({G}%.1f %s{R})",i+1,clientName,speed,g_szUnitMess_Name[g_iPlugin_Unit]);
			}
			else if(i < 3){
				
				Client_PrintToChat(client,false,"{G}%d{R}. {G}%s (%.1f %s) %N",i+1,clientName,speed,g_szUnitMess_Name[g_iPlugin_Unit],client);
				//PrintToChat(client,"{G}%d{R}. {G}%s (%.1f %s)",i+1,clientName,speed,g_szUnitMess_Name[g_iPlugin_Unit]);
			}
		}
	}
}

stock SortBestRound(){
	
	new size = GetArraySize(g_hClient_Name);
	
	//we want to swap the current and the next array index so size-1 to prevent out of bounds at the end.
	new i,j;
	for (i=0;i<size;i++) { 
		for (j=i;j<size;j++) { 
			if (GetArrayCell(g_hClient_MaxRoundSpeed,i) < GetArrayCell(g_hClient_MaxRoundSpeed,j)) {
				
				SwapArrayItems(g_hClient_UserId,i,j);
				SwapArrayItems(g_hClient_SteamId,i,j);
				SwapArrayItems(g_hClient_Name,i,j);
				SwapArrayItems(g_hClient_MaxRoundSpeed,i,j);
				SwapArrayItems(g_hClient_MaxGameSpeed,i,j);
			} 
		} 
	}
}

stock SortBestGame(){
	
	new size = GetArraySize(g_hClient_Name);
	
	//we want to swap the current and the next array index so size-1 to prevent out of bounds at the end.
	new i,j;
	for (i=0;i<size;i++) { 
		for (j=i;j<size;j++) { 
			if (GetArrayCell(g_hClient_MaxGameSpeed,i) < GetArrayCell(g_hClient_MaxGameSpeed,j)) {
				
				SwapArrayItems(g_hClient_UserId,i,j);
				SwapArrayItems(g_hClient_SteamId,i,j);
				SwapArrayItems(g_hClient_Name,i,j);
				SwapArrayItems(g_hClient_MaxRoundSpeed,i,j);
				SwapArrayItems(g_hClient_MaxGameSpeed,i,j);
			} 
		} 
	}
}

stock SetClientMaxRoundSpeedAll(Float:units){
	
	new size = GetArraySize(g_hClient_MaxRoundSpeed);
	
	for(new i=0;i<size;i++){
		
		SetArrayCell(g_hClient_MaxRoundSpeed,i,units);
	}
}

stock SetClientMaxRoundSpeed(client, Float:units){
	
	new index = FindValueInArray(g_hClient_UserId,GetClientUserId(client));
	
	if(index == -1){
		return;
	}
	
	SetArrayCell(g_hClient_MaxRoundSpeed,index,units);
}

stock SetClientMaxGameSpeedAll(Float:units){
	
	new size = GetArraySize(g_hClient_MaxGameSpeed);
	
	for(new i=0;i<size;i++){
		
		SetArrayCell(g_hClient_MaxGameSpeed,i,units);
	}
}

stock SetClientMaxGameSpeed(client, Float:units){
	
	new index = FindValueInArray(g_hClient_UserId,GetClientUserId(client));
	
	if(index == -1){
		return;
	}
	
	SetArrayCell(g_hClient_MaxGameSpeed,index,units);
}


stock ClientAll_Initialize(){
	
	for(new client=1;client<=MaxClients;client++){
		
		if(!IsClientInGame(client) || !IsClientAuthorized(client)){
			continue;
		}
		
		Client_Initialize(client);
	}
}

stock Client_Initialize(client){
	
	//Variables
	Client_InitializeVariables(client);
	
	if(!IsClientInGame(client)){
		return;
	}
	
	
	if(!IsClientAuthorized(client)){
		return;
	}
	
	//Functions
	InsertNewPlayer(client);
}

stock Client_InitializeVariables(client){
	
	//Variables:
	//g_bClientSetZero[client] = false;
}


stock InsertNewPlayer(client){
	
	new String:clientName[STEAMAUTH_LENGTH];
	GetClientName(client,clientName,sizeof(clientName));
	
	new String:clientAuth[STEAMAUTH_LENGTH];
	if(IsFakeClient(client)){
		Format(clientAuth,sizeof(clientAuth),"BOT_%s",clientName);
	}
	else {
		GetClientAuthString(client,clientAuth,sizeof(clientAuth));
	}
	
	new id = FindStringInArray(g_hClient_SteamId,clientAuth);
	
	if(id == -1){
		
		PushArrayCell(g_hClient_UserId,GetClientUserId(client));
		PushArrayString(g_hClient_SteamId,clientAuth);
		PushArrayString(g_hClient_Name,clientName);
		PushArrayCell(g_hClient_MaxRoundSpeed,0.0);
		PushArrayCell(g_hClient_MaxGameSpeed,0.0);
	}
	else {
		
		SetArrayCell(g_hClient_UserId,id,GetClientUserId(client));
		SetArrayString(g_hClient_Name,id,clientName);
	}
	
	return id;
}



