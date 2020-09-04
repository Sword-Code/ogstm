#!/bin/env ipython
from __future__ import print_function
import datetime
import matplotlib 
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
import csv, glob, os, sys

from basins import V2 as OGS
from commons import timerequestors
from commons.time_interval import TimeInterval
from commons.Timelist import TimeList
from matchup.statistics import *
import netCDF4 as NC4

from ancillary import *


SIM_MAIN_FOLDER   = sys.argv[1]                # SIM_MAIN_FOLDER = '/gpfs/scratch/userexternal/eterzic0/1D_RTM/TESTS/'

CSV_FILE          = open(sys.argv[2], 'r')     # CSV_FILE        = open('../../preproc/RADIATIVE_INWATER/Simulations.csv', 'r')

READER            = csv.reader(CSV_FILE)

SAT_DIR           = '/gpfs/scratch/userexternal/eterzic0/RRS_SAT/ORIG/'

VARLIST           = ['RRS412', 'RRS443', 'RRS490', 'RRS510', 'RRS555' , 'RRS670']

nMonths     = 12
MONTHS      = np.arange(1, nMonths + 1)
months_str  = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D']
nSub        = len(OGS.med.basin_list)
nStat       = 4
nWl         = len(VARLIST)

basin_list_abbrev = ['ALB', 'SWM1', 'SWM2', 'NWM', 'TYR1', 'TYR2', 'ADR1', 'ADR2', 'AEG', 'ION1', 'ION2', 'ION3', 'LEV1', 'LEV2', 'LEV3', 'LEV4' ]

for iline, line in enumerate(READER):  # each line is one simulation
	if iline == 0:
		continue    # we are skipping the header

	SIM_FOLDER = SIM_MAIN_FOLDER + line[0]  # first column of a line

	if not os.path.isdir(SIM_FOLDER + '/RRS'):      # If the RRS folder does not exist, skip it
		continue

	print('Plotting pcolor Rrs of simulation %s ... '%line[0], end = '')

	if not os.path.isdir(SIM_MAIN_FOLDER + '/PLOTS'):   
		os.mkdir(SIM_MAIN_FOLDER + '/PLOTS')                # create the PLOTS folder within the simulation folder

	if not os.path.isdir(SIM_MAIN_FOLDER + '/PLOTS/PCOLOR'):   
		os.mkdir(SIM_MAIN_FOLDER + '/PLOTS/PCOLOR')        # create the PCOLOR folder within the PLOTS folder

	if not os.path.isdir(SIM_MAIN_FOLDER + '/PLOTS/PCOLOR/Rrs_CLIM'):   
		os.mkdir(SIM_MAIN_FOLDER + '/PLOTS/PCOLOR/Rrs_CLIM')     # create the Rrs folder within the PCOLOR folder

	datelist = []
	filelist = []

	for ifile, filename in enumerate(glob.glob(SIM_FOLDER + '/RRS/*.nc')):

		aux1     = filename.strip('.nc')
		aux2     = aux1.strip(SIM_FOLDER  + '/RRS/')
		wmo, date, lon, lat  = aux2.split('_')

		actualtime = datetime.datetime.strptime(date, '%Y%m%d-%H:%M:%S')

		datelist.append(actualtime)
		filelist.append(filename)

	datelist, filelist = (list(t) for t in zip(*sorted(zip(datelist, filelist))))

	TL                 = TimeList(datelist, forceFrequency='daily')
	TL.filelist        = filelist
	TL.timeinterval    = TimeInterval.fromdatetimes(datelist[0], datelist[-1])

	lon                = [float(filename.strip('.nc').strip(SIM_FOLDER + '/RRS/').split('_')[2])  for filename in filelist]
	lat                = [float(filename.strip('.nc').strip(SIM_FOLDER + '/RRS/').split('_')[3])  for filename in filelist]

	
	RRS_SUB = np.zeros((nWl, nSub, nMonths, nStat))

	for ivar, var in enumerate(VARLIST):

		for isub, sub in enumerate(OGS.med):         # Loop over subbasins

			for iMonth, month in enumerate(MONTHS):  # Loop over climatological months

				CLIM_MONTH_req = timerequestors.Clim_month(month)

				ilist, wlist   =  TL.select(CLIM_MONTH_req)

				Rrs_model = np.nan*np.ones((1,))
				Rrs_sat   = np.nan*np.ones((1,))

				for ii, w in zip(ilist,wlist):

					if not sub.is_inside(lon[ii], lat[ii]): 				
						Rrs_model = np.concatenate((Rrs_model, np.array([np.nan])))
						Rrs_sat   = np.concatenate((Rrs_sat,   np.array([np.nan])))
						continue

					ncin     = NC4.Dataset(TL.filelist[ii], 'r')

					Rrs_model = np.concatenate((Rrs_model, ncin.variables['Rrs'][:,ivar]))
			
					ncin.close()

					filelist_SAT = SAT_DIR + TL.Timelist[ii].strftime("%Y%m%d") + "_d-OC_CNR-L3-" + var + "-MedOC4AD4_SAM_1KM-MED-REP-v02.nc"

					ncSAT        = NC4.Dataset(filelist_SAT, 'r')

					lonSAT       = ncSAT.variables['lon'][:]
					latSAT       = ncSAT.variables['lat'][:]

					ilon         = np.argmin(np.abs(lonSAT - lon[ii]))
					ilat         = np.argmin(np.abs(latSAT - lat[ii]))

					Rrs_sat       = np.concatenate((Rrs_sat, [ncSAT.variables[var][0,ilat,ilon].filled(fill_value=np.nan)]))

					ncSAT.close()

				L = matchup(Rrs_model[1:], Rrs_sat[1:])

				RRS_SUB[ivar, isub, iMonth, :] = [L.Model.mean(), L.Ref.mean(), L.bias(), L.RMSE() ]

		fig1,ax1 = plt.subplots(2,2)
		fig1.set_size_inches(11.69, 8.27)

		plot_pcolor(fig1, ax1, RRS_SUB[ivar, :,:,0], RRS_SUB[ivar,:,:,1], RRS_SUB[ivar,:,:,2], RRS_SUB[ivar,:,:,3], 'Rrs', var[3:], basin_list_abbrev, months_str)

		fig1.tight_layout()

		OUTDIR = SIM_MAIN_FOLDER + '/PLOTS/PCOLOR/Rrs_CLIM/' 

		OUTNAME = line[-1].replace(" ", "_").replace(",", "")

		fig1.savefig(OUTDIR     + line[0]  + '_plot_SAT_' + OUTNAME + '_' + var +  '.png', dpi=300)

		print('Saving figure ' + line[0]  + ' plot ' + var + line[-1])
		sys.stdout.flush()

		plt.close(fig1)

CSV_FILE.close()

	
