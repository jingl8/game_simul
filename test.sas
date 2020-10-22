/*********************************************************************************************/
/*                                                                                           */
/*   The Wholesale Scoring Model Group executes at the segment level before the Wholesale    */
/*   Evaluation Model Group begins execution at the loan level. The output variables from    */
/*   the Wholesale Scoring Model Group are scored to each loan based on their segmentation   */ 
/*   as controlled by CounterpartyID.                                                        */
/*                                                                                           */
/*   The purpose of this Scoring Model Group is to calculate values relevant to BMO's        */
/*   PD methodology at a segment level and then pass those values                            */
/*   to each loan within the segment before further processing at the loan level.            */
/*                                                                                           */
/*********************************************************************************************/

/***************************************************************************/
/*                                                                         */  
/*   The INIT block runs once prior to any segment-level evaluations.      */
/*   This block is used to control initialization logic general to all     */
/*   segments in the analysis.                                             */
/*                                                                         */
/***************************************************************************/

beginblock INIT;

	/**********************************************************************************/
	/*                                                                                */
	/*   Assign string lengths suitable for the analysis of all Wholesale Products.   */
	/*                                                                                */
	/**********************************************************************************/

	length pd_model 				$32 		   		   
		   rating_grp 				$4	  
		   pd_seg 					$5  
		   pd_scale_col 			$6   
		   pmx_row 					$64
		   pmx_row_adj 				$24	   
		   pmx_col_adj 				$4;
		   
endblock;

/**********************************************************************************************/
/*                                                                                            */
/*   The INST_INIT block runs once per segment prior to the evaluation of said segment.       */
/*   This block is used to control logic general to a specific segment for the entirety       */ 
/*   of the analysis (e.g., assigning static variables).                                      */
/*                                                                                            */
/*   Note, INST_INIT is an alias for LOAN_INIT. INST_INIT was chosen to be used here in the   */
/*   Scoring Model Group as we are doing a segment level analysis rather than loan level.     */
/*                                                                                            */
/**********************************************************************************************/
       
beginblock INST_INIT;  
	
	/********************************************************************/
	/*                                                                  */
	/*   Handle logic for loans in default at portfolio snapshot date   */
	/*                                                                  */
	/********************************************************************/
	
	if compress(scan(CounterpartyID,2,"_")) in ("DEF","DF") then do;
		in_default_flag  = 1;
        lifetime_seg     = 1;
    end;
    else in_default_flag = 0; 
	
	/*******************************************************************/
	/*                                                                 */
	/*   Assign product-specific character strings used to determine   */
	/*   PD segment for models and inputs to parameter matrix calls.   */
	/*                                                                 */
	/*   The intermediate variable lifetime_seg is assigned to         */
	/*   control how many horizons the segment is evaluated for.       */
	/*                                                                 */
	/*******************************************************************/
	
	non_tf_portfolio = 1;      
	select(SEG_PORTFOLIO);
	    when ("WUSCORP")   pd_scale_col = 'corp';
	    when ("WUSPCNI")   pd_scale_col = 'us_cni';  
	    when ("WUSPCCRE")  pd_scale_col = 'us_cre';
	    when ("WUSTRNSPF") do;
	    	pd_scale_col = 'tf';
	    	non_tf_portfolio = 0;
	    end;
	end;  
	
	if (in_default_flag ne 1) then do;
		/* Set rating group for all wholesale ptf */
		if (non_tf_portfolio) then do;
			rating_grp   = substr(SEG_MASTER_SCALE_RATING,1,1);
			pmx_col_adj  = compress(tranwrd(SEG_MASTER_SCALE_RATING,'-','_'));
			pd_seg       = compress('seg_'||rating_grp);
		end;
		else do;
			rating_grp   = compress(scan(CounterpartyID,2,"_"));
			pmx_col_adj  = compress('TF_'||rating_grp);
		    pd_seg 		 = compress('seg'||rating_grp);
		end;
	end;  
	
	call pmxelem(portfolio_max_horizon,SEG_PORTFOLIO,'max_horizon',lifetime_seg,rc);
	max_seg_horizon = lifetime_seg;
	
    
    /********************************************/
    /*                                          */
    /* Add Flexibility - Call Control table pmx */ 
    /*                                          */
    /********************************************/
    call pmxelem(control_table_wsl, SEG_PORTFOLIO, 'PD_MODEL_SWITCH',    _PD_MODEL_SWITCH_, rc);     /* Champion(1) or Challenger(2) */
	call pmxelem(control_table_wsl, SEG_PORTFOLIO, 'PD_RS_PERIOD',       _PD_RS_PERIOD_, rc);        /* PD R&S period = 36           */
	call pmxelem(control_table_wsl, SEG_PORTFOLIO, 'PD_MEAN_REVERSION',  _PD_MEAN_REVERSION_, rc);   /* PD mean reversion speed = 0  */
	call pmxelem(control_table_wsl, SEG_PORTFOLIO, 'LR_PD_PERIOD',       _LR_PD_PERIOD_, rc);        /* PD long run period = 24      */
	call pmxelem(control_table_wsl, SEG_PORTFOLIO, 'PD_RESIDUAL_PERIOD', _PD_RESIDUAL_PERIOD_, rc);  /* PD residual period = 60      */
	call pmxelem(control_table_wsl, SEG_PORTFOLIO, 'prepayment',         _if_prepay_, rc);           /* Turn on and off perpayment   */
	call pmxelem(control_table_wsl, SEG_PORTFOLIO, 'prepayment_type',    _prepay_tp_, rc);			 /* Conditional or unconditional */
	
	if SEG_PORTFOLIO = "WUSTRNSPF" and rating_grp in ("7", "8") 
	then call pmxelem(denorm_wsl, compress(SEG_PORTFOLIO||"_HOR_1_Segment_0"||rating_grp), 'max_pd_horizon', _MAX_PD_CURVE_HOR_, rc);
	else call pmxelem(denorm_wsl, compress(SEG_PORTFOLIO||"_HOR_1_Segment_"||rating_grp), 'max_pd_horizon', _MAX_PD_CURVE_HOR_, rc);
	
	_MAX_PD_CURVE_HORIZON_ = _MAX_PD_CURVE_HOR_ * 3;
	
	_PD_RS_P_       = min(_MAX_PD_CURVE_HORIZON_, _PD_RS_PERIOD_);                      /* horizon = 36  */
    _PD_MR_SPEED_   = min(_MAX_PD_CURVE_HORIZON_, _PD_RS_P_ + _PD_MEAN_REVERSION_);     /* horizon = 36  */
	_LR_PD_P_       = min(_MAX_PD_CURVE_HORIZON_, _PD_MR_SPEED_ +_LR_PD_PERIOD_) ;      /* horizon = 60  */
	_PD_RESIDUAL_P_ = _LR_PD_P_ + _PD_RESIDUAL_PERIOD_;                                 /* horizon = 120 */
    
endblock;

/*******************************************************************************************/
/*                                                                                         */
/*   The MAIN block contains the logic to evaluate each segment within the internal        */
/*   loops of the system (loop through horizons per loop through Monte Carlo simulations   */
/*   per loop through scenarios). If the model group is not designated as Monte Carlo,     */ 
/*   then a single pass through horizons occurs for each segment per scenario. Prior to    */
/*   evaluation through forecast horizons, a segment is evaluated a single time at the     */
/*   portfolio run-as-of date (simulationHorizon = 0).                                     */
/*                                                                                         */
/*******************************************************************************************/
 
beginblock MAIN;

if _PD_MODEL_SWITCH_ = 1 then do; /* Start Champion PD Model */

	/**************************************************************************************/
	/*                                                                                    */
	/*   Define Segment Default Flag and Segment Lifetime Output Variables                */
	/*   By defining these outputs in SimulationHorizon 0, the values are available for   */
	/*   processing in the LOAN_INIT block of the Evaluation Model Group downstream.      */
	/*                                                                                    */
	/**************************************************************************************/
	
	SEG_DEFAULT_FLAG_MIP 	 = in_default_flag;
	SEG_LIFETIME		 	 = lifetime_seg;


	/* Skip the remaining logic in the Portfolio Run-as-of Date (simulationHorizon = 0) */
	if simulationHorizon = 0 then return;
	
	/***************************************************************************/
	/*                                                                         */
	/*   Logic for the first horizon of each scenario.                         */
	/*   This is the point at which intermediate variables are reset           */
	/*   to their initial values at the start of each scenario. It is          */
	/*   important to reset such variables due to the fact that intermediate   */
	/*   variables are automatically retained in HP Risk.                      */
	/*                                                                         */
    /***************************************************************************/
	
	if (simulationHorizon eq 1) then do;
		unscaled_pd_seg   = 0;
		marginal_pd_seg   = 0;
		lag_pd            = 0;	
		_12m_pd           = 0;	
		lifetime_pd       = 0;	
		last_pmx_horizon  = 0;
			
		/* parameters for 3 new PD models */
		incremental_pd    = 0;
		prob_survival     = 1;
		pd_combined       = 0;			
		lag_mean          = 0;
	end;
	
	/****************************************************************************/
	/*                                                                          */
	/*   Logic for evaluation of a segment at each horizon                      */	
	/*   Segments are only evaluated during their lifetime                      */
	/*   Standard PD Methodology is only applicable to Non-Defaulted Segments   */
	/*                                                                          */
    /****************************************************************************/
	
	if (simulationHorizon <= max_seg_horizon) then do;
	
		/****************************************************************/
		/*                                                              */
		/*   Forecast Quarter Analysis                                  */
		/*   Computations required for each forecast quarter are done   */
		/*   once at the beginning of the forecast quarter.             */
		/*                                                              */
		/****************************************************************/
	
		if (mod(simulationHorizon,3) = 1) then do; 
		
			/* Define horizon in terms of quarters */
			hrz = ceil(simulationHorizon/3);
			
			/****************************************************************/
			/*                                                              */
			/*   Define PD model based on segment and forecast horizon      */
			/*                                                              */
			/****************************************************************/
			
			if simulationHorizon <= 12 then fc_qtr="1";
			else fc_qtr="2";
			
			if (simulationHorizon <= lifetime_seg) then do;
		
				if (in_default_flag ne 1) then pd_model = compress(strip(pd_scale_col)||'_cecl_pd'||strip(pd_seg)||"_p"||fc_qtr);
							
			end;

		   	/***********************************************************************/
		   	/*                                                                     */
			/*    Generate row arguments for distribution parameter matrix calls   */
		   	/*                                                                     */
		   	/***********************************************************************/
		   	
			if SEG_PORTFOLIO in ("WUSCORP","WUSPCNI","WUSPCCRE") then do;
				if (simulationHorizon <= lifetime_seg) then do;
					if (in_default_flag ne 1) then pmx_row = compress("HOR_"||strip(hrz)||"_Segment_"||rating_grp);				
				end;		
			end;
			
			else if (SEG_PORTFOLIO = "WUSTRNSPF") and (in_default_flag ne 1) then do;
				if rating_grp in ("7", "8") then pmx_row = compress("HOR_"||strip(hrz)||"_Segment_0"||rating_grp);
				else pmx_row = compress("HOR_"||strip(hrz)||"_Segment_"||rating_grp);
			end;
			
			/***************************************************************/
			/*                                                             */
			/*   PD Scaling for non-tf portfolios                          */
			/*   PD Scaling is only applicable to Non-Defaulted Segments   */
			/*                                                             */
			/***************************************************************/
			
			if (simulationHorizon = 1) then do;
				if SEG_PORTFOLIO in ("WUSCORP","WUSPCNI","WUSPCCRE") then do;
					if (in_default_flag ne 1)  then call pmxelem(static_wsl_pd_scale, SEG_MASTER_SCALE_RATING, pd_scale_col, _pd_scale_, rc);				
				end;
				
				/* No PD scaling is performed for TF Portfolio */
				else if (SEG_PORTFOLIO eq "WUSTRNSPF") and (in_default_flag ne 1) then _pd_scale_ = 1;
			end;
			
			/*************************************************************************/
		   	/*                                                                       */
			/*    Historical distribution parameter matrix calls.                    */
		   	/*    The intermediate variables _mean_ and _stdev_ are populated from   */
		   	/*    calls to the historical distribution for Non-Defaulted Segments.   */
		   	/*                                                                       */
		   	/*************************************************************************/
			
			if (non_tf_portfolio) then do;
				if (simulationHorizon <= lifetime_seg) then do;
					if (in_default_flag ne 1) then do;
						call pmxelem(denorm_wsl, compress(SEG_PORTFOLIO||"_"||pmx_row), 'mean', _mean_, rc);
						call pmxelem(denorm_wsl, compress(SEG_PORTFOLIO||"_"||pmx_row), 'stdev', _stdev_, rc);
					end;			
				end;		
			end;
			else do;
				if (in_default_flag ne 1) then do;
					call pmxelem(denorm_wsl, compress(SEG_PORTFOLIO||"_"||pmx_row), 'mean', _mean_, rc);
					call pmxelem(denorm_wsl, compress(SEG_PORTFOLIO||"_"||pmx_row), 'stdev', _stdev_, rc);
				end;			
			end;
			
			/* call prepayment pmx, with flexibility */
			if _if_prepay_ = 1 and _prepay_tp_ = 2 and (in_default_flag ne 1) then call pmxelem(prepay_wsl, compress(SEG_PORTFOLIO||"_"||pmx_row), 'prepayment', _prepayment_, rc);
			else if _if_prepay_ = 0 and _prepay_tp_ = 2 then _prepayment_ = 0;
			
		end; /* end of quarterly calculation */
		
		/****************************************************************/
		/*                                                              */
		/*   Forecast Horizon Analysis                                  */
		/*   These computations are required at each forecast horizon   */
		/*                                                              */
		/****************************************************************/
		
		/***********************************************************************/
	   	/*                                                                     */
		/*   PD adjustment parameter matrix calls.                             */
		/*   PD adjustment is only applicable to Non-Defaulted Segments.       */
	   	/*   The intermediate variables pd_adj is                              */
	   	/*   populated from calls to the pd adjustment parameter matrix.       */
	   	/*                                                                     */
		/***********************************************************************/
		
		
		if (simulationHorizon <= _LR_PD_P_) then do; /* Horizon <= 60 */		
			/* The intermediate variable pmx_row_adj is used in the call to the pd adjustment parameter matrix. */
			pmx_row_adj = compress(SEG_PORTFOLIO||"_HOR_"||simulationHorizon);
			
			/* Apply maturity adjustment to CORP and CNI only. New conditional PD models do not use mat_adj */
			if SEG_PORTFOLIO in ("WUSCORP", "WUSPCNI") then do;
				if (simulationHorizon <= lifetime_seg) then do;
					if (in_default_flag ne 1)  then call pmxelem(mat_adj_wsl, pmx_row_adj, pmx_col_adj, pd_adj, rc);			
				end;				
			end;
		end;
		
		/* Set pd_adj to one beyond 60 months */
		else do;
			if (in_default_flag ne 1)  and (simulationHorizon <= lifetime_seg)  then pd_adj = 1 ;
		end;
		
		/************************************************************ BEGIN PD ************************************************************/
		
		/****************************************************************/
		/*                                                              */
		/*   Calculate Marginal PD for Non-Defaulted Segments           */
		/*                                                              */
    	/****************************************************************/
    	
    	
		if (simulationHorizon <= lifetime_seg) then do;
	    	if (in_default_flag ne 1) then do;
				
				/* Horizon > 60 - add flexibility */
				if simulationHorizon > _LR_PD_P_ then do;
				
					if simulationHorizon <= _PD_RESIDUAL_P_ then do; /* Horizon < 120 */
						if SEG_PORTFOLIO in ("WUSPCCRE","WUSTRNSPF") then do;
							unscaled_pd_seg = normalized_dr;
							marginal_pd_seg = (max(unscaled_pd_seg  * _pd_scale_, 0.000025)/3);
							incremental_pd = prob_survival * marginal_pd_seg;
							prob_survival = prob_survival * (1- marginal_pd_seg - _prepayment_/3);
							pd_combined = incremental_pd;
						end;
						else do;
							normalized_dr = (-lag_pd / (_PD_RESIDUAL_P_ - (last_pmx_horizon))) * simulationHorizon + (lag_pd / (_PD_RESIDUAL_P_ - (last_pmx_horizon))) * _PD_RESIDUAL_P_;
							unscaled_pd_seg = normalized_dr;
							marginal_pd_seg = unscaled_pd_seg;	
							pd_combined = marginal_pd_seg;
						end;
					end;
					
					else do;
					   pd_combined = 0;
					end; 
					
				end;
				
				/* Marginal PD using PD models - Horizon <= 36 */
				else if (simulationHorizon le _PD_RS_P_) then do; 
					/* Modifiled TF seg-8 phase-2 */
					if fc_qtr eq "2" and seg_portfolio in ("WUSTRNSPF") and strip(rating_grp) eq "8" then do;
						call missing(dr);
						normalized_dr = _mean_;
					end;
					else do;
						call run_model(pd_model);
						dr = _model_.result;
						normalized_dr = dr * _stdev_ + _mean_;
					end;
					unscaled_pd_seg = normalized_dr;
			
					if SEG_PORTFOLIO in ("WUSPCCRE","WUSTRNSPF") then do;
						marginal_pd_seg = (max(unscaled_pd_seg  * _pd_scale_, 0.000025)/3);
						incremental_pd = prob_survival * marginal_pd_seg;
						prob_survival = prob_survival * (1- marginal_pd_seg - _prepayment_/3);
						lag_pd = unscaled_pd_seg;
						pd_combined = incremental_pd;						
					end;
					else do;
						marginal_pd_seg = (max(unscaled_pd_seg  * _pd_scale_, 0.000025)/3) * pd_adj;
						lag_pd = unscaled_pd_seg;
						pd_combined = marginal_pd_seg;
					end;	
				
					last_pmx_horizon = simulationHorizon;					
				end;
				
				/* Mean reversion speed = 0 */
				else if (_PD_RS_P_ < simulationHorizon <= _PD_MR_SPEED_) then do; 
					lag_mean_row = compress(SEG_PORTFOLIO||"_"||"HOR_"||strip(ceil(_PD_MR_SPEED_/3))||"_Segment_"||rating_grp);
					call pmxelem(denorm_wsl, lag_mean_row ,'mean', lag_mean, rc);
					
					normalized_dr = (lag_pd - lag_mean)/(_PD_MR_SPEED_ - last_pmx_horizon)*(_PD_MR_SPEED_ - simulationHorizon) + lag_mean;
					
					if SEG_PORTFOLIO in ("WUSPCCRE","WUSTRNSPF") then do;
						unscaled_pd_seg = normalized_dr;
						marginal_pd_seg = (max(unscaled_pd_seg  * _pd_scale_, 0.000025)/3);
						incremental_pd = prob_survival * marginal_pd_seg;
						prob_survival = prob_survival * (1- marginal_pd_seg - _prepayment_/3);
						pd_combined = incremental_pd;
					end;
					
					else do;
						unscaled_pd_seg = normalized_dr;
						marginal_pd_seg = (max(unscaled_pd_seg  * _pd_scale_, 0.000025)/3) * pd_adj;
						pd_combined     = marginal_pd_seg;
					end;
				end;
				
				/* 36 < Horizon <= 60 */
				else do;
					normalized_dr =  _mean_;
					unscaled_pd_seg = normalized_dr;
					
					if SEG_PORTFOLIO in ("WUSPCCRE","WUSTRNSPF") then do;
						marginal_pd_seg = (max(unscaled_pd_seg  * _pd_scale_, 0.000025)/3);
						incremental_pd = prob_survival * marginal_pd_seg;
						prob_survival = prob_survival * (1- marginal_pd_seg - _prepayment_/3);
						lag_pd = incremental_pd;
						pd_combined = incremental_pd;
					end;
					else do;
						marginal_pd_seg = (max(unscaled_pd_seg  * _pd_scale_, 0.000025)/3) * pd_adj;
						lag_pd = marginal_pd_seg;
						pd_combined = marginal_pd_seg;
					end;
					
					lag_mean = _mean_;
					last_pmx_horizon = simulationHorizon;				
				end;
				
			end; /* end of default flag ne 1 */
			
			/* Assign Value of 1 to Marginal PD for Defaulted Segments */
			else do;
				pd_combined = 1; 
			end;
		
			/***************************************************************************/
			/*                                                                         */
			/*   Business rule for I-1 PD treatment for Non-TF Wholesale Portfolios   */
			/*                                                                         */
			/***************************************************************************/
			
			if (non_tf_portfolio) and (SEG_MASTER_SCALE_RATING = 'I-1') then pd_combined = 0.000001; 
			
			/*********************************************/
			/*                                           */
			/*   Logic to ensure lifetime_pd <= 0.9999   */
			/*                                           */
			/*********************************************/
			
			/* Replace marginal_pd_seg with pd_combined */
			if 0 < lifetime_pd < 0.9999 and lifetime_pd + pd_combined >= 0.9999 then do;
				  pd_combined = 0.9999 - lifetime_pd;
				  lag_pd = pd_combined;
			end;
			if lifetime_pd >= 0.9999 then do;
				  pd_combined = 0;
				  lag_pd = pd_combined;
			end;   
			
			/****************************************/
			/*                                      */
			/*   Calculate PD 12M and PD Lifetime   */
			/*                                      */
	    	/****************************************/
			
			if simulationhorizon <= 12 then _12m_pd = min(0.9999, _12m_pd + pd_combined);
			lifetime_pd = min(0.9999, lifetime_pd + pd_combined);
			
		end; /* End of simulationHorizon <= lifetime_seg */
		
		/************************************************************ END PD *************************************************************/
		
		if (non_tf_portfolio) and (SEG_BASEL_PRE_CRM_PD_CURRENT >= 1) then do;
			lifetime_pd = 1;
		    _12m_pd = 1; 
		end;
		
	end; /* End of simulationHorizon <= max_seg_horizon */
	
	/*********************************************/
	/*                                           */
	/*   Assign Segment-Level Output Variables   */
	/*                                           */
	/*********************************************/
	SEG_UNSCALED_PD     = unscaled_pd_seg; 	
	SEG_MARGINAL_PD     = pd_combined;        
	SEG_PD_12M          = _12m_pd;
	SEG_PD_LIFETIME     = lifetime_pd;

	/* Output variables only for new conditional PD models */
	if SEG_PORTFOLIO in ("WUSPCCRE","WUSTRNSPF") then do;
		SEG_SURVIVAL         = prob_survival;
		SEG_CONDITIONAL_PD   = marginal_pd_seg;
		SEG_UNCONDITIONAL_PD = incremental_pd;
		SEG_PREPAYMENT       = _prepayment_;
	end;
	else do;
		SEG_SURVIVAL         = . ;
		SEG_CONDITIONAL_PD   = . ;
		SEG_UNCONDITIONAL_PD = . ;
		SEG_PREPAYMENT       = . ;
	end;

end; /* End of Champion PD Model */

else if _PD_MODEL_SWITCH_ = 2 then do; /* Start Challenger PD Model */

end; /* End of Challenger PD Model */
	
endblock;
