#pragma rtGlobals=1		// Use modern global access method. - Leave this line as is, as 1st line!
#pragma ModuleName= Iolite_ActiveDRS  	//Leave this line as is, as 2nd line!
StrConstant DRS_Version_No= "3.0"  	//Leave this line as is, as 3rd line! V 2.0 uses new channelname info parser "GetInfoFromChannelName(ChannelName, mode)" to handle channel name suffixes
//V3.0: IndexContentInSample is now in wt%!!! Saves confusion between this DRS and Trace_Elements_IS and is also how people normally discuss IS contents.
//****End of Header Lines - do not disturb anything above this line!****

//****The global strings (SVar) and variables (NVar) below must always be present. Do not alter their names, alter only text to the right of the "=" on each line.**** (It is important that this line is left unaltered)
	GlobalString				IndexChannel 							="Ca43"
	GlobalString				ReferenceStandard 						="G_NIST612"
	GlobalString				DefaultIntensityUnits						="CPS"
	//**** Below are some optional global strings and variables with pre-determined behaviour. If you wish to include these simply remove the two "//" at the beginning of the line. Similarly, if you wish to omit them, simply comment them using "//"
	GlobalVariable			MaskThreshold 							=5e3
	GlobalVariable			MaskEdgeDiscardSeconds 				=1
	GlobalString				StandardisationMethod					="Internal Elemental Standard"
	GlobalString				OutputUnits								="ppm"
	GlobalString				CalculateLODs							="No"
	GlobalString				LODmethod								="Normal"
	GlobalString				BeamSecondsMethod					="Rate of Change"
	GlobalVariable			BeamSecondsSensitivity					=4
	GlobalVariable			IndexContentInSample 					=40.04

	//**** Any global strings or variables you wish to use in addition to those above can be placed here. You may name these how you wish, and have as many or as few as you like**** (It is important that this line is left unaltered)

	//**** End of optional global strings and variables**** (It is important that this line is left unaltered)
	//certain optional globals are built in, and have pre-determined lists. these are currently: "StandardisationMethod", "OutputUnits"
	//Note that the above values will be the initial values every time the DRS is opened for the first time, but can then be overwritten for that experiment after that point via the button "Edit DRS Variables". This means that the settings for the above will effectively be stored within the experiment, and not this DRS (this is a good thing)
	//DO NOT EDIT THE ABOVE IF YOU WISH TO EDIT THESE VALUES WITHIN A PARTICULAR EXPERIMENT. THESE ARE THE STARTING VALUES ONLY. THEY WILL ONLY BE LOOKED AT ONCE WHEN THE DRS IS OPENED FOR THE FIRST TIME (FOR A GIVEN EXPERIMENT).


	//**** Initialisation routine for this DRS.  Will be called each time this DRS is selected in the "Select DRS" popup menu (i..e usually only once).
Function InitialiseActiveDRS() //If init func is required, this line must be exactly as written.   If init function is not required it may be deleted completely and a default message will print instead at initialisation.
	SVAR nameofthisDRS=$ioliteDFpath("Output","S_currentDRS") //get name of this DRS (which should have been already stored by now)
	Printf "\r\t** Standardised trace element Data Reduction Scheme, \"" + nameofthisDRS + "\", Version " + DRS_Version_No + "\r"
	//	Printf "\t** Specified index channel: \t%s\r\t** Index content in unknowns: \t%1.3f\r\t** Specified standard material: \t%s\r\r"//the following have been removed, they would require additional referencing of global strings that seems unnecessarily complicated---IndexChannel,IndexContentInSample,ReferenceStandard //and some basic info on the constants used
End //**end of initialisation routine


//****Start of actual Data Reduction Scheme.  This is run every time raw data is added or the user changes any input parameter or integration Try to keep it to no more than a few seconds!
Function RunActiveDRS() //The DRS function name must be exactly as written here.  Enter the function body code below.
	
	ProgressDialog()	//Show progress indicator to show where the DRS is up to
	
	//the next 5 lines reference all of the global strings and variables in the header of this file for use in the main code of the DRS that follows.
	string currentdatafolder = GetDataFolder(1)
	setdatafolder $ioliteDFpath("DRSGlobals","")
	SVar IndexChannel, ReferenceStandard, DefaultIntensityUnits, OutputUnits, BeamSecondsMethod, StandardisationMethod, CalculateLODs, LODmethod
	NVar MaskThreshold, MaskEdgeDiscardSeconds, IndexContentInSample, BeamSecondsSensitivity
	setdatafolder $currentdatafolder

	DRSabortIfNotWave(ioliteDFpath("Splines",IndexChannel+"_Baseline_1"))	//Abort if [index]_Baseline_1 is not in the Splines folder, otherwise proceed with DRS code below..
	SVAR ListOfOutputChannels=$ioliteDFpath("Output","ListOfOutputChannels") //"ListOfOutputChannels" is already in the Output folder, and will be empty ("") prior to this function being called.
	SVAR ListOfIntermediateChannels=$ioliteDFpath("Output","ListOfIntermediateChannels")
	SVAR ListOfInputChannels=$ioliteDFpath("input","GlobalListOfInputChannels") //Get reference to "GlobalListOfInputChannels", in the Input folder, and is a list of the form "ChannelName1;ChannelName2;..."
	ListOfOutputChannels = ""	
	ListOfIntermediateChannels = ""	
	//Now create the global time wave for intermediate and output waves, based on the index isotope  time wave  ***This MUST be called "index_time" as some or all export routines require it, and main window will look for it
	wave Index_Time = $MakeIndexTimeWave()	//create the index time wave using the external function - it tries to use the index channel, and failing that, uses total beam
	variable NoOfPoints=numpnts(Index_Time) //Make a variable to store the total number of time slices for the output waves
	wave IndexOut = $InterpOntoIndexTimeAndBLSub(IndexChannel)	//Make an output wave for Index isotope (as baseline-subtracted intensity)

	//Then create a seconds since shutter-opened wave, based on the index channel just created
wave Beam_Seconds=$DRS_MakeBeamSecondsWave(IndexOut,BeamSecondsSensitivity, BeamSecondsMethod) //This is determined by an external function which can be fine-tuned using the single sensitivity parameter.  Let me know if it fails!
	//**important - the two waves just created are intended as outputs, and so must be added to the listOfOutputs to be visible to the main control window and export fiunctions:

	ListOfOutputChannels+="Beam_Seconds;"+IndexChannel+"_"+DefaultIntensityUnits+";" // add the names of the beam seconds and index channel  waves just created to the list of outputs
	ListOfOutputChannels+= IndexChannel + "_" + DefaultIntensityUnits + ";" // add the names of the beam seconds and index channel  waves just created to the list of outputs

	ListOfIntermediateChannels += IndexChannel+"_"+DefaultIntensityUnits+";"
	
	//Make output mask waves, and apply them to the initial output channels.  Mask waves are composed of the values 1 and NAN,for multiplication with intermediate and output waves
	Wave Mask=$DRS_CreateMaskWave(IndexOut, MaskThreshold, MaskEdgeDiscardSeconds, "PrimaryMask", "StaticAbsolute")  //create primary mask, to be used on the intermediate channels. 

	SetProgress(10, "Starting baseline subtraction...")

	//Baseline-subtract and ratio to the (already baseline-subtracted) index chanel, for every remaining channel
	variable CurrentChannelNo=0,NoOfChannels=itemsinlist(ListOfInputChannels) //Create local variables to hold the current input channel number and the total number of input channels
	String NameOfCurrentChannel,CurrentElement, CurrentSuffix //Create a local string to contain the name of the current channel, and its corresponding element
	Do //Start to loop through the available channels
		NameOfCurrentChannel=StringFromList(CurrentChannelNo,ListOfInputChannels) //Get the name of the nth channel from the input list
		
		//Need to change the line below to read in any suffixes etc and add it to the end of the BLsub channel name
		
		CurrentElement=GetInfoFromChannelName(NameOfCurrentChannel, "element") //get name of the element

		if(cmpstr(CurrentElement,"Null")!=0 && cmpstr(NameOfCurrentChannel, IndexChannel)!=0) //if this element is not "null" (i.e. is an element), and it is not the index isotope, then..
			wave ThisChannelBLsub = $InterpOntoIndexTimeAndBLSub(NameOfCurrentChannel)		//use this external function to interpolate the input onto index_time then subtract it's baseline
			ThisChannelBLsub *= mask
			ListOfIntermediateChannels+=NameOfCurrentChannel+"_"+DefaultIntensityUnits+";" //Add the name of this new output channel to the list of outputs
		endif //Have now created a (baseline-subtracted channel)/(baseline-subtracted index) output wave for the current input channel, unless it was TotalBeam or index
		
		SetProgress(10+((CurrentChannelNo+1)/NoOfChannels)*20,"Processing baselines")	//Update progress for each channel
		
		CurrentChannelNo+=1 //So move the counter on to the next channel..
	While(CurrentChannelNo<NoOfChannels) //..and continue to loop until the last channel has been processed.
	//Now all intermediate waves required by this DRS have been created.

	//NOTE: If you need to remove spikes from any baseline-subtracted waves, do that here.

	SetProgress(30, "Baselines subtracted...")

	//make some variables/strings that will be used in multiple data reduction methods below.
	Variable IndexElementConcInStd, ThisElementConcInStd, CurrentMassNo, OutputUnitDivisor
	string Units
	//first branch of the DRS options. If baseline subtract is selected for the data reduction method, then make the list of outputs include all baseline subtracted (intermediates) and halt the DRS from doing anything else.
	if(cmpstr(StandardisationMethod, "Baseline subtract only")==0)
		ListOfOutputChannels += ListOfIntermediateChannels
		ListOfIntermediateChannels = ""
		return 1
	elseif(cmpstr(StandardisationMethod, "Internal Elemental Standard")==0)	//otherwise, are we using the "normal" method. If so need to make elements vs the index element here.
		//make baseline subtracted channels ratio'ed to the index element. that is what the following loop does
		CurrentChannelNo=0
		Do //Start to loop through the available channels
			NameOfCurrentChannel=StringFromList(CurrentChannelNo,ListOfInputChannels) //Get the name of the nth channel from the input list
			CurrentElement=GetInfoFromChannelName(NameOfCurrentChannel, "element") //get name of the element
			
			if(cmpstr(CurrentElement,"Null")!=0 && cmpstr(NameOfCurrentChannel, IndexChannel)!=0 ) //if this element is not "null" (i.e. is an element), and it is not the index isotope, then..
				Wave ThisChannelBLsub=$ioliteDFpath("CurrentDRS",NameOfCurrentChannel+"_"+DefaultIntensityUnits)
				Wave ThisChannel_vs_Index=$MakeioliteWave("CurrentDRS",NameOfCurrentChannel+"_v_"+IndexChannel,n=NoOfPoints) //Create this channel's output wave, of the pre-determined length and create a reference to it.
				ThisChannel_vs_Index=ThisChannelBLsub/IndexOut	//simply take the baseline subtracted wave and divide by the (baseline subtracted) index element wave
				ListOfIntermediateChannels+=NameOfCurrentChannel+"_v_"+IndexChannel+";" //Add the name of this new output channel to the list of outputs
			endif //Have now created a (baseline-subtracted channel)/(baseline-subtracted index) output wave for the current input channel, unless it was TotalBeam or index
			
			SetProgress(30+((CurrentChannelNo+1)/NoOfChannels)*30,"Processing ratio channels")	//Update progress for each channel
			
			CurrentChannelNo+=1 //So move the counter on to the next channel..
		While(CurrentChannelNo<NoOfChannels) //..and continue to loop until the last channel has been processed.
	endif
	//so now from here on we will only need to deal with semi-quantitative and internal element with external standard (whatever the formal names of these end up being)
	//For both of these we need a standard, so check for this
	RecalculateIntegrations("*","*") //recalculate the integration data for all existing integration types, for the list of channels just created
	
	SetProgress(60, "Ratio Channels calculated...")
	
	DRSAbortIfNotWave(ioliteDFpath("Splines",StringFromList(0,ListOfIntermediateChannels)+"_"+ReferenceStandard))	//Abort if there is not yet a spline of the expected standard type, for the first intermediate channel

	//so, is it the "normal" approach of using an internal standard element and and external standard glass?
	if(cmpstr(StandardisationMethod, "Internal Elemental Standard")==0)
		//This subsection of the DRS calculates output waves: Get absolute concentrations in the specifed ratio unit, for all elements for which data are availiable for this standard.
		CurrentChannelNo=0  ; NoOfChannels=itemsinlist(ListOfInputChannels) //Create local variables to hold the current input channel number and the total number of input channels
		
		//Need to change line below to use new GetElementFromIsotope code
		IndexElementConcInStd=GetValueFromStandard(GetInfoFromChannelName(IndexChannel, "element"),ReferenceStandard)//Store the abundance of index isotope in the standard
		
		OutputUnitDivisor=RatioUnit2AbsoluteAbundance(OutputUnits) //Get the equivalent absolute abundance ratio for the specified ratio unit
		Units=CleanUpUnitName(OutputUnits) //get a "cleaned" version of the ratio unit name (e.g. "ng/g" will become "ng_g", "%" will become "Percent", "ppm" will stay"ppm")
		Do //Start to loop through the available channels
			NameOfCurrentChannel=StringFromList(CurrentChannelNo,ListOfInputChannels) //Get the name of the nth channel from the input list
			CurrentElement=GetInfoFromChannelName(NameOfCurrentChannel, "element") //get name of the element ("Null" if channel is not an isotope)
			CurrentMassNo=str2num( GetInfoFromChannelName(NameOfCurrentChannel, "massNo") )//get current mass number (NAN if channel is not an isotope, except special case where Varian has "___" as mass number meaning "total" e.g. Pb___ is 206Pb+207Pb+208Pb)
			CurrentSuffix = GetInfoFromChannelName(NameOfCurrentChannel, "suffix")
			if(cmpstr(CurrentSuffix, "Null" ) == 0)	//If this channel has no suffix
				CurrentSuffix = ""		//Set to zero characters so that it won't change the channel name
			endif
			
			if(cmpstr(CurrentElement,"Null")!=0 && cmpstr(NameOfCurrentChannel, IndexChannel)!=0 && cmpstr(num2str(CurrentMassNo), "-666")!=0) //if this element is not "null" (i.e. is an element), and it is not the index isotope, then..
				ThisElementConcInStd=GetValueFromStandard(CurrentElement,ReferenceStandard) //get the value of this element from the specified standard
				Wave ThisChannelvsIndex=$ioliteDFpath("CurrentDRS",NameOfCurrentChannel+"_v_"+IndexChannel)  //and create a reference to its intermediate ratio to index wave
				if(numtype(ThisElementConcInStd)==0) //If a finite number was returned fom the standard, then there was a value for this std, so..
					wave SplineOfThisChannelVIndex = $InterpSplineOntoIndexTime(NameOfCurrentChannel+"_v_"+IndexChannel, ReferenceStandard)
					Wave ThisChannelConcOut=$MakeioliteWave("CurrentDRS",CurrentElement+CurrentSuffix+"_"+Units+"_m"+num2str(CurrentMassNo),n=NoOfPoints)//Create this channel's output wave, of the pre-determined length, including unit name and mass no., and reference it
					ThisChannelConcOut=ThisChannelvsIndex/SplineOfThisChannelVIndex*(ThisElementConcInStd/IndexElementConcInStd) * (IndexContentInSample/100) / OutputUnitDivisor //Calc, per point: Conc=[C/I]meas.smp/[C/I]meas.std*[C/I]knwn.std*I[knwn.smp]/units*mask
					ListOfOutputChannels+=CurrentElement+CurrentSuffix+"_"+Units+"_m"+num2str(CurrentMassNo)+";" //Add the name of this new output channel to the list of outputs
				Else //otherwise, value of this element in std was NAN, so cannot convert to the ratio unit - output baseline-subtracted intensity units instead..
					Wave ThisChannelIntenOut=$MakeioliteWave("CurrentDRS",NameOfCurrentChannel+"_"+DefaultIntensityUnits,n=NoOfPoints) //Create and reference this channel's output wave, of the pre-determined length
					ThisChannelIntenOut=ThisChannelvsIndex*IndexOut //multiply by index to get back to base-line subtracted CPS, and mask the result to remove stds
					ListOfOutputChannels+=NameOfCurrentChannel+"_"+DefaultIntensityUnits+";" //Add the name of this new output channel to the list of outputs
				endif //now this channel has been processed if it was an isotope, either as a concentration or as CPS
			endif // end of code for this channel
			//***Special case for "total" channels from the varian (e.g. Pb___)
			if(cmpstr(CurrentElement,"Null")!=0 && cmpstr(NameOfCurrentChannel, IndexChannel)!=0 && cmpstr(num2str(CurrentMassNo), "-666")==0) //if this element is not "null" (i.e. is an element), and it is not the index isotope, but the mass number has the code "-666" then it is a "total" channel from the varian, so...
				ThisElementConcInStd=GetValueFromStandard(CurrentElement,ReferenceStandard) //get the value of this element from the specified standard
				Wave ThisChannelvsIndex=$ioliteDFpath("CurrentDRS",NameOfCurrentChannel+"_v_"+IndexChannel)  //and create a reference to its intermediate ratio to index wave
				if(numtype(ThisElementConcInStd)==0) //If a finite number was returned fom the standard, then there was a value for this std, so..
					wave SplineOfThisChannelVIndex = $InterpSplineOntoIndexTime(NameOfCurrentChannel+"_v_"+IndexChannel, ReferenceStandard)
					Wave ThisChannelConcOut=$MakeioliteWave("CurrentDRS",CurrentElement+"_"+Units+"_m"+"___",n=NoOfPoints)//Create this channel's output wave, of the pre-determined length, including unit name and mass no., and reference it
					ThisChannelConcOut=ThisChannelvsIndex/SplineOfThisChannelVIndex*(ThisElementConcInStd/IndexElementConcInStd)*IndexContentInSample/OutputUnitDivisor //Calc, per point: Conc=[C/I]meas.smp/[C/I]meas.std*[C/I]knwn.std*I[knwn.smp]/units*mask
					ListOfOutputChannels+=CurrentElement+CurrentSuffix+"_"+Units+"_m"+"___"+";" //Add the name of this new output channel to the list of outputs
				Else //otherwise, value of this element in std was NAN, so cannot convert to the ratio unit - output baseline-subtracted intensity units instead..
					Wave ThisChannelIntenOut=$MakeioliteWave("CurrentDRS",NameOfCurrentChannel+"_"+DefaultIntensityUnits,n=NoOfPoints) //Create and reference this channel's output wave, of the pre-determined length
					ThisChannelIntenOut=ThisChannelvsIndex*IndexOut //multiply by index to get back to base-line subtracted CPS, and mask the result to remove stds
					ListOfOutputChannels+=NameOfCurrentChannel+"_"+DefaultIntensityUnits+";" //Add the name of this new output channel to the list of outputs
				endif //now this channel has been processed if it was an isotope, either as a concentration or as CPS
			endif // end of code for this channel
			
			SetProgress(60+((CurrentChannelNo+1)/NoOfChannels)*30,"Calculating concentrations...")	//Update progress for each channel
			
			CurrentChannelNo+=1 //So move the channel counter on to the next channel..
		While(CurrentChannelNo<NoOfChannels) //..and continue to loop until the last channel has been processed.
		//End of per-channel output wave calculation

	endif
	//the above is a big endif. it is the end of the subsection that handles creating outputs using an internal standard element and an external standard.

	//the below is the subsection that handles creating outputs using a semi-quantitative approach
	if(	cmpstr(StandardisationMethod, "Semi quantitative")==0)
		//This part of the DRS calculates output waves: Get absolute concentrations in the specifed ratio unit, for all elements for which data are availiable for this standard.
		CurrentChannelNo=0  ; NoOfChannels=itemsinlist(ListOfInputChannels) //Create local variables to hold the current input channel number and the total number of input channels
		OutputUnitDivisor=RatioUnit2AbsoluteAbundance(OutputUnits) //Get the equivalent absolute abundance ratio for the specified ratio unit
		Units=CleanUpUnitName(OutputUnits) //get a "cleaned" version of the ratio unit name (e.g. "ng/g" will become "ng_g", "%" will become "Percent", "ppm" will stay"ppm")
		Do //Start to loop through the available channels
			NameOfCurrentChannel=StringFromList(CurrentChannelNo,ListOfInputChannels) //Get the name of the nth channel from the input list
			CurrentElement=GetInfoFromChannelName(NameOfCurrentChannel, "element") //get name of the element ("Null" if channel is not an isotope)
			CurrentMassNo=str2num( GetInfoFromChannelName(NameOfCurrentChannel, "massNo") )//get current mass number (NAN if channel is not an isotope)
			CurrentSuffix = GetInfoFromChannelName(NameOfCurrentChannel, "suffix")
			if(cmpstr(CurrentSuffix, "Null" ) == 0)	//If this channel has no suffix
				CurrentSuffix = ""		//Set to zero characters so that it won't change the channel name
			endif
			
			if(cmpstr(CurrentElement,"Null")!=0) //if this element is not "null" (i.e. is an element), then..
				ThisElementConcInStd=GetValueFromStandard(CurrentElement,ReferenceStandard) //get the value of this element from the specified standard
				Wave ThisChannelBLSub=$ioliteDFpath("CurrentDRS",NameOfCurrentChannel+"_"+DefaultIntensityUnits)  //and create a reference to its intermediate ratio to index wave
			
				if(numtype(ThisElementConcInStd)==0) //If a finite number was returned fom the standard, then there was a value for this std, so..
					wave ThisChnlBLSubInStandard = $InterpSplineOntoIndexTime(NameOfCurrentChannel+"_"+DefaultIntensityUnits,ReferenceStandard) //interpolate and reference its [channel]_v_[index] spline wave.
					Wave ThisChannelConcOut=$MakeioliteWave("CurrentDRS",CurrentElement+CurrentSuffix+"_"+Units+"_SQ"+"_m"+num2str(CurrentMassNo),n=NoOfPoints)//Create this channel's output wave, of the pre-determined length, including unit name and mass no., and reference it
					Variable scale = ThisElementConcInStd/OutputUnitDivisor
					FastOp ThisChannelConcOut=(scale)*ThisChannelBLSub/ThisChnlBLSubInStandard //Calc, per point: Conc=meas.smp/meas.std*knwn.std/SampVsStdAbltn/units
					ListOfOutputChannels+=CurrentElement+CurrentSuffix+"_"+Units+"_SQ"+"_m"+num2str(CurrentMassNo)+";" //Add the name of this new output channel to the list of outputs
			
				Else //otherwise, value of this element in std was NAN, so cannot convert to the ratio unit - output baseline-subtracted intensity units instead..
					ListOfOutputChannels+=NameOfCurrentChannel+"_"+DefaultIntensityUnits+";" //Add the name of this intermediate  channel to the list of output channels (a single wave is able to exist as both an intermediate and an output simultaneously)
			
				endif //now this channel has been processed if it was an isotope, either as a concentration or as CPS
			endif // end of code for this channel
			
			SetProgress(60+((CurrentChannelNo+1)/NoOfChannels)*30,"Calculating concentrations...")	//Update progress for each channel
			
			CurrentChannelNo+=1 //So move the channel counter on to the next channel..
		While(CurrentChannelNo<NoOfChannels) //..and continue to loop until the last channel has been processed.
		//End of per-channel output wave calculation
		ListOfOutputChannels = removeFromList(IndexChannel+"_"+DefaultIntensityUnits+";", ListOfOutputChannels, ";", 0)
	endif
	//the above is a big endif. it is the end of the subsection that handles creating outputs using a semi-quantitative method.

	//***Limits of detection section***
	IF(GrepString(CalculateLODs, "(?i)yes") == 1)		//If the user has selected to calculate LODs (Off by default)
		SetProgress(90,"Calculating LODs...")	//Update progress for each channel
		String ListOfUnknowns = GetListOfNotStdIntegTypes("m")	//Produces a list of non-standard integration type, e.g. Output_1
		Variable Indx=0
		ListOfUnknowns = RemoveFromList("m_Baseline_1", ListOfUnknowns)
		Do
			If(Strlen(ListOfUnknowns)==0)	//In case the user hasn't selected any unknowns yet
				Print Time()+": No unknown integration types found yet"
				SetProgress(100,"Finished DRS")	//Update progress for each channel
				Break
			Endif
			String IntegShortName=Stringfromlist(Indx,ListOfUnknowns)[2,inf]
			LimitsOfDetection(IntegShortName, IndexContentInSample, LODmethod)
			Indx += 1
		While(Indx<itemsinlist(ListOfUnknowns))	
	ENDIF
	
Wave U_Ca = $makeioliteWave("CurrentDRS", "U_Ca_Ratio", n=NoOfPoints)
	
	Wave U = $ioliteDFPath("CurrentDRS", "U_ppm_SQ_m238")
	Wave Ca = $ioliteDFpath("CurrentDRS", "Ca_ppm_SQ_m43")
	U_Ca = U/Ca
	
	ListOfOutputChannels += "U_Ca_Ratio"
	
	SetProgress(100,"Finished DRS")	//Update progress for each channel

end   //****End of DRS function.  Write any required external sub-routines below this point****

Function MakeUCaTable(IntStr)
	String IntStr
	
	Wave im = $ioliteDFpath("integration", "m_" + IntStr)
	Wave/T tm = $ioliteDFpath("integration", "t_"+ IntStr)
	Variable NoOfIntegrations = DimSize(im,0)-1	

	Wave UCaData = $MakeIoliteWave("CurrentDRS", "U_Ca_Wtd_"+IntStr, n = NoOfIntegrations)
	
	String currentDF = getdatafolder(1)
	setdatafolder $ioliteDFpath("CurrentDRS", "")
	Make/O/T/N=(NoOfIntegrations) $("U_Ca_Labels_" + IntStr)
	Wave/T UCaDataLabels = $ioliteDFpath("CurrentDRS", "U_Ca_Labels_" + IntStr)
	setdatafolder currentDF
	
	Variable i
	For (i = 1; i <= NoOfIntegrations; i =i + 1)
		UCaData[i-1] = CalculateWeightedUCa(IntStr, i)
		UCaDataLabels[i-1] = tm[i][0][1]
	EndFor
	
	Edit UCaDataLabels, UCaData
End

Function CalculateWeightedUCa(IntStr, IntNo)
	String IntStr
	Variable IntNo
	
	Wave im = $ioliteDFpath("integration", "m_" + IntStr)
	Variable NoOfIntegrations = DimSize(im,0)-1
	
	If (IntNo > NoOfIntegrations)
		Print "Specified integration index doesn't exist"
		Return 0
	EndIf
	
	Wave Index_Time = $ioliteDFpath("CurrentDRS", "Index_Time")
	Wave Beam_Seconds = $ioliteDFpath("CurrentDRS", "Beam_Seconds")
	Wave U_Ca_Ratio = $ioliteDFpath("CurrentDRS", "U_Ca_Ratio")
	
	Variable WeightedUCa = 0
	
	// Loop through time-slices of current integration
	Variable thisstarttime = im[IntNo][0][%$"Median Time"]-im[IntNo][0][%$"Time Range"]
	Variable thisendtime = im[IntNo][0][%$"Median Time"]+im[IntNo][0][%$"Time Range"]
	
	Variable thisstartpoint = ForBinarySearch(index_time, thisstarttime) + 1

	if(numtype(index_time[thisstartpoint]) == 2)	//if the resulting point was a NaN
		thisstartpoint += 1		//then add 1 to it
	endif

	Variable thisendpoint = ForBinarySearch(index_time, thisendtime)

	if(thisendpoint == -2)	//if the last selection goes over the end of the data
		thisendpoint = numpnts(index_time) - 1
	endif

	Variable dx = (20.60/30)*(Beam_Seconds[thisendpoint]-Beam_Seconds[thisendpoint-1])  // 20.6 = total ablation depth in microns; 30 = total analysis length (s)
	Variable TotalWeight = 0
	
	Variable j
	For (j=thisstartpoint; j<=thisendpoint; j = j + 1)
		Variable x = (20.60/30)*Beam_Seconds[j] 

		Variable Weight = 2*(PVS(8,8-x) - PVS(8,8-x-dx))/VS(8)
		//print x, Weight, TotalWeight, U_Ca_Ratio[j]
		if (numtype(U_Ca_Ratio[j]) == 0 && Weight > 0)
			TotalWeight += Weight
			WeightedUCa += Weight * U_Ca_Ratio[j]
		Endif
	EndFor
	
//	print "Weighted U/Ca Ratio = ", WeightedUCa
	
	Return WeightedUCa/TotalWeight
End

Function VS(r)
	Variable r
	Return (4/3)*pi*r^3
End

Function PVS(r, h)
	Variable r, h
	
	Return (1/3)*pi*h^2*(3*r-h)
End

//**** Shut-down routine for this DRS.  Will be called each time this DRS is closed down to be replaced by another (which could be itself again), via the DRS selection popup menu
Function TidyUpActiveDRS() //If shutdown func is required, this line must be exactly as written.   If init function is not required it may be deleted completely and nothing will happen
	SVAR nameofthisDRS=$ioliteDFpath("Output","S_currentDRS") //get name of this DRS (which should have been already stored by now)
	If(SVAR_Exists(nameofthisDRS))		//BP: I just put this in because sometimes we get a null string error, usually after updating an old experiment. If the string aint there, this function does very little.
		//All this function currently does is print a close-down message.  A more useful thing for a shut-down function to do is tidy up any tables, graphs, panels that this DRS has opened, or deleting any waves or folders it has made that need not be kept, etc.
		Printf "\t** Standardised trace element Data Reduction Scheme \"%s\" is closing down **\r",nameofthisDRS //print shut-down message
	Endif
End //**end of shut-down routine



//the below 2 function are for the automatic setup of baselines and intermediates on the traces window.
Function AutoBaselines(buttonstructure) //Build the main display and integration window --- This is based off a button, so has button structure for the next few lines
	STRUCT WMButtonAction&buttonstructure
	if( buttonstructure.eventCode != 2 )
		return 0  // we only want to handle mouse up (i.e. a released click), so exit if this wasn't what caused it
	endif  //otherwise, respond to the popup click
	ClearAllTraces()
	AutoTrace(0, "Ca43", 0, 15000, extraflag = "Primary")	//see the autotrace function for what these mean.	set both max and min to zero for autoscale.
	AutoTrace(1, "Sr88", 0, 5000)	//see the autotrace function for what these mean.
	AutoTrace(2, "Ba138", 0, 4000)	//see the autotrace function for what these mean.
	AutoTrace(3, "Pb208", 0, 5000)	//see the autotrace function for what these mean.
	AutoTrace(4, "Th232", 0, 2000)	//see the autotrace function for what these mean.
	AutoTrace(5, "U238", 0, 800, extraflag = "Right")	//see the autotrace function for what these mean.
	AutoTrace(6, "Ce140", 0, 500, extraflag = "Hidden")	//see the autotrace function for what these mean.
end

Function AutoIntermediates(buttonstructure) //Build the main display and integration window --- This is based off a button, so has button structure for the next few lines
	STRUCT WMButtonAction&buttonstructure
	if( buttonstructure.eventCode != 2 )
		return 0  // we only want to handle mouse up (i.e. a released click), so exit if this wasn't what caused it
	endif  //otherwise, respond to the popup click
	ClearAllTraces()
	AutoTrace(0, "Ca43_CPS", 0, 0)	//see the autotrace function for what these mean.	set both max and min to zero for autoscale.
	AutoTrace(1, "Sr88_v_Ca43", 0, 0)	//see the autotrace function for what these mean.
	AutoTrace(2, "Ba138_v_Ca43", 0, 0)	//see the autotrace function for what these mean.
	AutoTrace(3, "Pb208_v_Ca43", 0, 0, extraflag = "Primary")	//see the autotrace function for what these mean.
	AutoTrace(4, "Th232_v_Ca43", 0, 0)	//see the autotrace function for what these mean.
	AutoTrace(5, "U238_v_Ca43", 0, 0, extraflag = "Right")	//see the autotrace function for what these mean.
	AutoTrace(6, "Ce140_v_Ca43", 0, 0, extraflag = "Hidden")	//see the autotrace function for what these mean.
end
