
MODULE ogstm_mpi_module

USE myalloc
USE mpi

implicit NONE



contains
!! mpp routines
!!
!! mynode
!! mpplnk_my
!! mpprecv
!! mppsend
!! mppwait
!! mppsync
!! mppstop
!!
!!!---------------------------------------------------------------------
!!!
!!!                       routine mynode
!!!                     ******************
!!!
!!!  Purpose :
!!!  ---------
!!!     Massively parallel processors
!!!     Find processor unit
!!!
!!   Input :
!!   -----
!!      argument                :
!!
!!   Modifications:
!!   --------------
!!       original  : 93-09 (M. Imbard)
!!       additions : 96-05 (j. Escobar)
!!       additions : 98-05 (M. Imbard, J. Escobar, L. Colombet )
!!                          SHMEM and MPI versions
!!----------------------------------------------------------------------

SUBROUTINE mynode

      INTEGER :: ierr
#ifdef key_mpp_mpi

      CALL mpi_comm_rank(mpi_comm_world,myrank,ierr)
      CALL mpi_comm_size(mpi_comm_world,mpi_glcomm_size,ierr)
      
#else
      mpi_glcomm_size = 1
      myrank = 1     
#endif

END SUBROUTINE

     
!!!---------------------------------------------------------------------
!!!
!!!                       routine mpplnk_my
!!!                     ******************
!!!
!!!  Purpose :
!!!  ---------
!!!      Message passing manadgement
!!!
!!   Method :
!!   -------
!!       Use mppsend and mpprecv function for passing mask between
!!       processors following neighboring subdomains.
!!
!!   Input :
!!   -----
!!      argument
!!              ptab            : variable array
!!              ktype           : define the nature of the grid-point
!!                  at which ptab is defined for 0
!!                                initialization
!!                  = 1 ,  T- and W-points
!!                  = 2 ,  U-point
!!                  = 3 ,  V-point
!!                  = 4 ,  F-point
!!                                = 11,  T-point only fold treatment
!!                                = 14,  F-point only fold treatment
!!        ksgn        : control of the sign change
!!                  = 0 , the sign is modified following
!!                  the type of b.c. used
!!                  = 1 , the sign of the field is un-
!!                  changed at the boundaries
!!      common
!!            /COMDOM/ : domain parameters
!!                    nlci   : first dimension of the local subdomain
!!                    nlcj   : second dimension of the local subdomain
!!                    nbondi : mark for "east-west local boundary"
!!                    nbondj : mark for "north-south local boundary"
!!                    noea   : number for local neighboring processors
!!                    nowe   : number for local neighboring processors
!!                    noso   : number for local neighboring processors
!!                    nono   : number for local neighboring processors
!!            /COMMPP/ : massively parallel processors
!!                    t3ew() : message passing arrays east-west
!!                    t3we() : message passing arrays west-east
!!                    t3ns() : message passing arrays north-south
!!                    t3sn() : message passing arrays south-north
!!
!!   Output :
!!   ------
!!      common
!!            /COMMPP/ : massively parallel processors
!!                    t3ew() : message passing arrays east-west
!!                    t3we() : message passing arrays west-east
!!                    t3ns() : message passing arrays north-south
!!                    t3sn() : message passing arrays south-north
!!   Workspace :
!!   ---------
!!             jk,jj,ji,jl,imigr,iihom,ijhom
!!
!!   External :
!!   --------
!!             mppsend,mpprecv
!!       or    shmem_put barrier shmem_udcflush
!!
!!
!!   References :                 no
!!   ----------
!!
!!   Modifications:
!!   --------------
!!       original  : 94-11 (M. Guyon)
!!       additions : 95-04 (j. Escobar, M. Imbard)
!!       additions : 98-05 (M. Imbard, J. Escobar, L. Colombet )
!!                          SHMEM and MPI versions
!!----------------------------------------------------------------------
 SUBROUTINE mpplnk_my(ptab)


!!----------------------------------------------------------------------
!!

      double precision ptab(jpk,jpj,jpi)

      double precision t3p1_my1(jpi,1,jpk,2)
      double precision t3p2_my1(jpi,1,jpk,2)

#ifdef key_mpp_mpi

      INTEGER jk,jj,ji,jl
      INTEGER imigr,iihom,ijhom,iloc,ijt,iju
      double precision zsgn
      INTEGER reqs1, reqs2, reqr1, reqr2
      INTEGER jn



!!
!!0. Initialization
!!-----------------
!!
!!Sign setting
!!...

zsign = 1.


!!     trcadvparttime = MPI_WTIME()




!!1. standard boundary treatment
!!------------------------------
!!
!!East-West boundary conditions
!!


              iihom = nlci-jpreci
              DO ji = iihom+1,jpi
                DO jk = 1,jpk
                  DO jj = 1,jpj
                    ptab(jk,jj,ji) = 0.e0
                  END DO
                END DO
              END DO

                  DO ji = 1,jpreci
                    DO jk = 1,jpk
                      DO jj = 1,jpj
                        ptab(jk,jj,ji) = 0.e0
                      END DO
                    END DO
                  END DO


!!
!!North-South boundary conditions
!!

          ijhom = nlcj-jprecj
          DO jj = ijhom+1,jpj
            DO jk = 1,jpk
              DO ji = 1,jpi
                ptab(jk,jj,ji) = 0.e0
              END DO
            END DO
          END DO

              DO jj = 1,jprecj
                DO jk = 1,jpk
                  DO ji = 1, jpi
                    ptab(jk,jj,ji) = 0.e0
                  END DO
                END DO
              END DO




!!
!!
!!2. East and west directions exchange
!!------------------------------------
!!
!!2.1 Read Dirichlet lateral conditions
!!


      IF(nbondi.ne.2) THEN
         ! jpreci = 1 from parini
         ! nreci =  2*jpreci from inimpp
         ! nlci = jpi
         ! iihom=jpi-2



          iihom=nlci-nreci
          jl = 1 ! it was a DO jl=1,jpreci, (with jpreci=1) now is forced jl=1
         DO jw=1,WEST_count_send
              jj = WESTpoints_send(1,jw)
              jk = WESTpoints_send(2,jw)
             tw_send(jw) = ptab(jk,jj,jpreci+jl)
         ENDDO
         DO jw=1,EAST_count_send
             jj = EASTpoints_send(1,jw)
             jk = EASTpoints_send(2,jw)
             te_send(jw) = ptab(jk,jj,iihom +jl)
         ENDDO


      ENDIF


!!
!!2.2 Migrations
!!
!!

      IF(nbondi.eq.-1) THEN ! We are at the west side of the domain
          CALL mppsend(2,te_send,EAST_count_send,noea,0,reqs1)
          CALL mpprecv(1,te_recv,EAST_count_recv,reqr1)
          !CALL mppsend(2,t3we_my1(1,1,1,1,1),imigr,noea,0,reqs1)
          !CALL mpprecv(1,t3ew_my1(1,1,1,1,2),imigr,reqr1)
          CALL mppwait(reqs1)
          CALL mppwait(reqr1)
      ELSE IF(nbondi.eq.0) THEN
          CALL mppsend(1, tw_send,WEST_count_send,nowe,0,reqs1)
          CALL mppsend(2, te_send,EAST_count_send,noea,0,reqs2)
          !CALL mppsend(1,t3ew_my1(1,1,1,1,1),imigr,nowe,0,reqs1)
          !CALL mppsend(2,t3we_my1(1,1,1,1,1),imigr,noea,0,reqs2)
          !CALL mpprecv(1,t3ew_my1(1,1,1,1,2),imigr,reqr1)
          !CALL mpprecv(2,t3we_my1(1,1,1,1,2),imigr,reqr2)
          CALL mpprecv(1,te_recv,EAST_count_recve,reqr1)
          CALL mpprecv(2,tw_recv,WEST_count_recv,reqr2)

          CALL mppwait(reqs1)
          CALL mppwait(reqs2)
          CALL mppwait(reqr1)
          CALL mppwait(reqr2)
      ELSE IF(nbondi.eq.1) THEN ! We are at the east side of the domain
          !CALL mppsend(1,t3ew_my1(1,1,1,1,1),imigr,nowe,0,reqs1)
          !CALL mpprecv(2,t3we_my1(1,1,1,1,2),imigr,reqr1)
          CALL mppsend(1,tw_send, WEST_count_send, nowe,0, reqs1)
          CALL mpprecv(2,tw_recv, WEST_count_recv, reqr1)
          CALL mppwait(reqs1)
          CALL mppwait(reqr1)
      ENDIF




!!
!!2.3 Write Dirichlet lateral conditions
!!
      iihom=nlci-jpreci
      jl = 1
      IF(nbondi.eq.0.or.nbondi.eq.1) THEN ! All but west boundary, we received from west

         DO jw=1,WEST_count_recv
              jj = WESTpoints_recv(1,jw)
              jk = WESTpoints_recv(2,jw)
             ptab(jk,jj,1)= tw_recv(jw)
         ENDDO

      ENDIF

      IF(nbondi.eq.-1.or.nbondi.eq.0) THEN ! All but east boundary, we received from east

        DO jw=1,EAST_count_recv
              jj = EASTpoints_recv(1,jw)
              jk = EASTpoints_recv(2,jw)
             ptab(jk,jj,jpi)= te_recv(jw)
        ENDDO

      ENDIF






!!
!!
!!3. North and south directions
!!-----------------------------
!!
!!3.1 Read Dirichlet lateral conditions
!!
!!       trcadvparttime = MPI_WTIME()
!!!!!$omp   parallel default(none) private(jn,jk,ji,jl,mytid,ijhom)
!!!!!$omp&      shared(packsize,nbondj,nlcj,nrecj,jprecj,jpk,jpi,t3sn_my1,t3ns_my1,ptab)
#ifdef __OPENMP11
        mytid = omp_get_thread_num()  ! take the thread ID
        jn=1
        IF(mytid +1 <= packsize) THEN
#else
      PACK_LOOP4: DO jn=1,packsize
#endif

      IF(nbondj.ne.2) THEN
          ijhom=nlcj-nrecj
!!
          DO jl=1,jprecj
            DO jk=1,jpk
              DO ji=1,jpi
                t3sn_my1(jk,jl,ji,jn+mytid,1)=ptab(jk,ijhom +jl,ji,jn+mytid)
                t3ns_my1(jk,jl,ji,jn+mytid,1)=ptab(ji,jprecj+jl,jk,jn+mytid)
              END DO
            END DO
          END DO
      ENDIF

#ifdef __OPENMP11
      END IF
!!!!!$omp    end parallel
#else
      END DO PACK_LOOP4
#endif

!!
!!3.2 Migrations
!!
!!
      imigr=jprecj*jpi*jpk*packsize

      IF(nbondj.eq.-1) THEN
          CALL mppsend(4,t3sn_my1(1,1,1,1,1),imigr,nono,0,reqs1)
          CALL mpprecv(3,t3ns_my1(1,1,1,1,2),imigr,reqr1)
          CALL mppwait(reqs1)
          CALL mppwait(reqr1)
      ELSE IF(nbondj.eq.0) THEN
          CALL mppsend(3,t3ns_my1(1,1,1,1,1),imigr,noso,0,reqs1)
          CALL mppsend(4,t3sn_my1(1,1,1,1,1),imigr,nono,0,reqs2)
          CALL mpprecv(3,t3ns_my1(1,1,1,1,2),imigr,reqr1)
          CALL mpprecv(4,t3sn_my1(1,1,1,1,2),imigr,reqr2)
          CALL mppwait(reqs1)
          CALL mppwait(reqs2)
          CALL mppwait(reqr1)
          CALL mppwait(reqr2)
      ELSE IF(nbondj.eq.1) THEN
          CALL mppsend(3,t3ns_my1(1,1,1,1,1),imigr,noso,0,reqs1)
          CALL mpprecv(4,t3sn_my1(1,1,1,1,2),imigr,reqr1)
          CALL mppwait(reqs1)
          CALL mppwait(reqr1)
      ENDIF
!!
!!
!!3.3 Write Dirichlet lateral conditions
!!
!!       trcadvparttime = MPI_WTIME()

!!!!!$omp   parallel default(none) private(jn,jk,ji,jl,mytid,ijhom)
!!!!!$omp&      shared(packsize,nbondj,nlcj,jprecj,jpk,jpi,t3sn_my1,t3ns_my1,ptab)
#ifdef __OPENMP11
        mytid = omp_get_thread_num()  ! take the thread ID
        jn=1
        IF(mytid +1 <= packsize) THEN
#else
      PACK_LOOP5: DO jn=1,packsize
#endif
      ijhom=nlcj-jprecj
      IF(nbondj.eq.0.or.nbondj.eq.1) THEN
          DO jl=1,jprecj
            DO jk=1,jpk
              DO ji=1,jpi
                ptab(jk,jl,ji,jn+mytid)=t3sn_my1(jk,jl,ji,jn+mytid,2)
              END DO
            END DO
          END DO
      ENDIF
!!
      IF(nbondj.eq.0.or.nbondj.eq.-1) THEN
          DO jl=1,jprecj
            DO jk=1,jpk
              DO ji=1,jpi
                ptab(jk,ijhom +jl,ji,jn+mytid)=t3ns_my1(jk,jl,ji,jn+mytid,2)
              END DO
            END DO
          END DO
      ENDIF

#ifdef __OPENMP11
      END IF
!!!!!$omp    end parallel
#else
      END DO PACK_LOOP5
#endif

!!
!!
!!4. north fold treatment
!!-----------------------
!!
!!4.1 treatment without exchange (jpni odd)
!!
!!     trcadvparttime = MPI_WTIME()

!!!!!$omp   parallel default(none) private(jn,jk,ji,ijt,iju,mytid,iloc)
!!!!!$omp&      shared(packsize,npolj,jpiglo,nimpp,ktype,jpk,nlci,zsgn,ptab,nlcj)
#ifdef __OPENMP11
        mytid = omp_get_thread_num()  ! take the thread ID
        jn=1
        IF(mytid +1 <= packsize) THEN
#else
      PACK_LOOP6: DO jn=1,packsize
#endif
      IF (npolj.eq.4) THEN
          iloc=jpiglo-2*(nimpp-1)
          IF ( ktype.EQ.1 .OR. ktype.EQ.11 ) THEN
              DO jk = 1, jpk
                DO ji = 2, nlci
                  ijt=iloc-ji+2
                  ptab(ji,nlcj,jk,jn+mytid) = zsgn * ptab(ijt,nlcj-2,jk,jn+mytid)
                END DO
                DO ji = nlci/2+1, nlci
                  ijt=iloc-ji+2
                  ptab(ji,nlcj-1,jk,jn+mytid) = zsgn * ptab(ijt,nlcj-1,jk,jn+mytid)
                END DO
              END DO
          ELSEIF ( ktype.EQ.2 ) THEN
              DO jk = 1, jpk
                DO ji = 1, nlci-1
                  iju=iloc-ji+1
                  ptab(ji,nlcj,jk,jn+mytid) = zsgn * ptab(iju,nlcj-2,jk,jn+mytid)
                END DO
                DO ji = nlci/2, nlci-1
                  iju=iloc-ji+1
                  ptab(ji,nlcj-1,jk,jn+mytid) = zsgn * ptab(iju,nlcj-1,jk,jn+mytid)
                END DO
              END DO
          ELSEIF ( ktype.EQ.3 ) THEN
              DO jk = 1, jpk
                DO ji = 2, nlci
                  ijt=iloc-ji+2
                  ptab(ji,nlcj-1,jk,jn+mytid) = zsgn * ptab(ijt,nlcj-2,jk,jn+mytid)
                  ptab(ji,nlcj  ,jk,jn+mytid) = zsgn * ptab(ijt,nlcj-3,jk,jn+mytid)
                END DO
              END DO
          ELSEIF ( ktype.EQ.4 .OR. ktype.EQ.14 ) THEN
              DO jk = 1, jpk
                DO ji = 1, nlci-1
                  iju=iloc-ji+1
                  ptab(ji,nlcj-1,jk,jn+mytid) = ptab(iju,nlcj-2,jk,jn+mytid)
                  ptab(ji,nlcj  ,jk,jn+mytid) = ptab(iju,nlcj-3,jk,jn+mytid)
                END DO
              END DO
          ENDIF
      ENDIF

#ifdef __OPENMP11
      END IF
!!!!!$omp    end parallel
#else
      END DO PACK_LOOP6
#endif

!!
!!4.1 treatment with exchange (jpni greater than 1)
!!
!!... sign ans sort are taken into a!!ount in the sender processor
!!

!!!!!$omp   parallel default(none) private(jn,jk,ji,ijt,iju,mytid,iloc)
!!!!!$omp&      shared(packsize,npolj,jpiglo,nimpp,nimppt,nono,ktype,jpk,jpi,t3p1_my1,t3p2_my1,zsgn,ptab,nlcj)
#ifdef __OPENMP11
        mytid = omp_get_thread_num()  ! take the thread ID
        jn=1
        IF(mytid +1 <= packsize) THEN
#else
      PACK_LOOP7: DO jn=1,packsize
#endif
      IF (npolj.eq.3) THEN
          iloc=jpiglo-(nimpp-1+nimppt(nono+1)-1)
          IF ( ktype.EQ.1 .OR. ktype.EQ.11 ) THEN
              DO jk=1,jpk
                DO ji=2,jpi
                  ijt=iloc-ji+2
                  if(ijt .ge. 1) then
                     t3p1_my1(ji,1,jk,jn+mytid,1) = zsgn * ptab(ijt,nlcj-2,jk,jn+mytid)
                     t3p2_my1(ji,1,jk,jn+mytid,1) = zsgn * ptab(ijt,nlcj-1,jk,jn+mytid)
                  else
                     t3p1_my1(ji,1,jk,jn+mytid,1) = zsgn * ptab(ijt+jpi,nlcj-2-1,jk,jn+mytid)
                     t3p2_my1(ji,1,jk,jn+mytid,1) = zsgn * ptab(ijt+jpi,nlcj-1-1,jk,jn+mytid)
                  endif
                END DO
              END DO
          ELSEIF ( ktype.EQ.2 ) THEN
              DO jk=1,jpk
                DO ji = 1, jpi-1
                  iju=iloc-ji+1
                  if(iju .ge. 1) then
                     t3p1_my1(ji,1,jk,jn+mytid,1) = zsgn * ptab(iju,nlcj-2,jk,jn+mytid)
                     t3p2_my1(ji,1,jk,jn+mytid,1) = zsgn * ptab(iju,nlcj-1,jk,jn+mytid)
                  else
                     t3p1_my1(ji,1,jk,jn+mytid,1) = zsgn * ptab(iju+jpi,nlcj-2-1,jk,jn+mytid)
                     t3p2_my1(ji,1,jk,jn+mytid,1) = zsgn * ptab(iju+jpi,nlcj-1-1,jk,jn+mytid)
                  endif
                END DO
              END DO
          ELSEIF ( ktype.EQ.3 ) THEN
              DO jk=1,jpk
                DO ji = 2, jpi
                  ijt=iloc-ji+2
                  if(ijt .ge. 1) then
                     t3p1_my1(ji,1,jk,jn+mytid,1) = zsgn * ptab(ijt,nlcj-2,jk,jn+mytid)
                     t3p2_my1(ji,1,jk,jn+mytid,1) = zsgn * ptab(ijt,nlcj-3,jk,jn+mytid)
                  else
                     t3p1_my1(ji,1,jk,jn+mytid,1) = zsgn * ptab(ijt+jpi,nlcj-2-1,jk,jn+mytid)
                     t3p2_my1(ji,1,jk,jn+mytid,1) = zsgn * ptab(ijt+jpi,nlcj-3-1,jk,jn+mytid)
                  endif
                END DO
              END DO
          ELSEIF ( ktype.EQ.4 .OR. ktype.EQ.14 ) THEN
              DO jk=1,jpk
                DO ji = 1, jpi-1
                  iju=iloc-ji+1
                  if(iju .ge. 1) then
                     t3p1_my1(ji,1,jk,jn+mytid,1) = ptab(iju,nlcj-2,jk,jn+mytid)
                     t3p2_my1(ji,1,jk,jn+mytid,1) = ptab(iju,nlcj-3,jk,jn+mytid)
                  else
                     t3p1_my1(ji,1,jk,jn+mytid,1) = ptab(iju+jpi,nlcj-2-1,jk,jn+mytid)
                     t3p2_my1(ji,1,jk,jn+mytid,1) = ptab(iju+jpi,nlcj-3-1,jk,jn+mytid)
                  endif
                END DO
              END DO
          ENDIF
        ENDIF

#ifdef __OPENMP11
      END IF
!!!!!$omp    end parallel
#else
      END DO PACK_LOOP7
#endif


!!
!!4.2 Migrations
          IF(npolj.eq.3) THEN
!!
!!
          imigr=jprecj*jpi*jpk*packsize


!!
          CALL mppsend(3,t3p1_my1(1,1,1,1,1),imigr,nono,0,reqs1)
          CALL mpprecv(3,t3p1_my1(1,1,1,1,2),imigr,reqr1)
          CALL mppwait(reqs1)
          CALL mppwait(reqr1)
          CALL mppsend(4,t3p2_my1(1,1,1,1,1),imigr,nono,0,reqs2)
          CALL mpprecv(4,t3p2_my1(1,1,1,1,2),imigr,reqr2)
          CALL mppwait(reqs2)
          CALL mppwait(reqr2)
!!
          ENDIF
!!
!!4.3 Write north fold conditions
!!

!!!!!$omp   parallel default(none) private(jn,jk,ji,mytid)
!!!!!$omp&      shared(packsize,npolj,ktype,jpk,nlci,ptab,t3p1_my1,nimpp,nlcj,t3p2_my1,jpjglo)
#ifdef __OPENMP11
        mytid = omp_get_thread_num()  ! take the thread ID
        jn=1
        IF(mytid +1 <= packsize) THEN
#else
      PACK_LOOP8: DO jn=1,packsize
#endif
         IF(npolj.eq.3) THEN
          IF ( ktype .EQ. 1  .or.ktype .eq. 11 ) THEN
              DO jk = 1, jpk
                DO ji = 2, nlci
                  ptab(ji,nlcj,jk,jn+mytid) = t3p1_my1(ji,1,jk,jn+mytid,2)
                END DO
              END DO
              IF(nimpp+nlcj/2 .gt. jpjglo/2) THEN
                  DO jk = 1, jpk
                    DO ji = 2, nlci
                      ptab(ji,nlcj-1,jk,jn+mytid) = t3p2_my1(ji,1,jk,jn+mytid,2)
                    END DO
                  END DO
              ENDIF
          ELSEIF ( ktype.EQ.2 ) THEn
              DO jk = 1, jpk
                DO ji = 1, nlci-1
                  ptab(ji,nlcj,jk,jn+mytid) = t3p1_my1(ji,1,jk,jn+mytid,2)
                END DO
              END DO
              IF(nimpp+nlcj/2 .gt. jpjglo/2) THEN
                  DO jk = 1, jpk
                    DO ji = 1, nlci-1
                      ptab(ji,nlcj-1,jk,jn+mytid) = t3p2_my1(ji,1,jk,jn+mytid,2)
                    END DO
                  END DO
              ENDIF
          ELSEIF ( ktype .EQ.3 ) THEN
              DO jk = 1, jpk
                DO ji = 2, nlci
                  ptab(ji,nlcj-1,jk,jn+mytid) = t3p1_my1(ji,1,jk,jn+mytid,2)
                  ptab(ji,nlcj  ,jk,jn+mytid) = t3p2_my1(ji,1,jk,jn+mytid,2)
                END DO
              END DO
          ELSEIF ( ktype .EQ.4 .or. ktype .EQ.14 ) THEN
              DO jk = 1, jpk
                DO ji = 1, nlci-1
                  ptab(ji,nlcj-1,jk,jn+mytid) = t3p1_my1(ji,1,jk,jn+mytid,2)
                  ptab(ji,nlcj  ,jk,jn+mytid) = t3p2_my1(ji,1,jk,jn+mytid,2)
                END DO
              END DO
          ENDIF
      ENDIF
#ifdef __OPENMP11
      END IF
!!!!!$omp    end parallel
#else
      END DO PACK_LOOP8
#endif

!!
!!
!!5. East and west directions exchange
!!------------------------------------
!!

!!!!!$omp   parallel default(none) private(jn,jl,jk,jj,mytid,iihom)
!!!!!$omp&      shared(packsize,npolj,nbondi,nlci,nreci,jpreci,jpk,jpj,t3ew_my1,t3we_my1,ptab)
#ifdef __OPENMP11
        mytid = omp_get_thread_num()  ! take the thread ID
        jn=1
        IF(mytid +1 <= packsize) THEN
#else
      PACK_LOOP9: DO jn=1,packsize
#endif
      IF (npolj.eq.3.or.npolj.eq.4) THEN
!!
!!5.1 Read Dirichlet lateral conditions
!!
          IF(nbondi.ne.2) THEN
              iihom=nlci-nreci
              DO jl=1,jpreci
                DO jk=1,jpk
!!Check the following
                  DO jj=1,jpj
                    t3ew_my1(jk,jj,jl,jn+mytid,1)=ptab(jj,jpreci+jl,jk,jn+mytid)
                    t3we_my1(jk,jj,jl,jn+mytid,1)=ptab(jj,iihom+jl,jk,jn+mytid)
                  END DO
                END DO
              END DO
          ENDIF
         ENDIF
#ifdef __OPENMP11
      END IF
!!!!!$omp    end parallel
#else
      END DO PACK_LOOP9
#endif

!!
!!5.2 Migrations
      IF (npolj.eq.3.or.npolj.eq.4) THEN
!!
!!
          imigr=jpreci*jpj*jpk*packsize

!!
          IF(nbondi.eq.-1) THEN
              CALL mppsend(2,t3we_my1(1,1,1,1,1),imigr,noea,0,reqs1)
              CALL mpprecv(1,t3ew_my1(1,1,1,1,2),imigr,reqr1)
              CALL mppwait(reqs1)
              CALL mppwait(reqr1)
          ELSE IF(nbondi.eq.0) THEN
              CALL mppsend(1,t3ew_my1(1,1,1,1,1),imigr,nowe,0,reqs1)
              CALL mppsend(2,t3we_my1(1,1,1,1,1),imigr,noea,0,reqs2)
              CALL mpprecv(1,t3ew_my1(1,1,1,1,2),imigr,reqr1)
              CALL mpprecv(2,t3we_my1(1,1,1,1,2),imigr,reqr2)
              CALL mppwait(reqs1)
              CALL mppwait(reqs2)
              CALL mppwait(reqr1)
              CALL mppwait(reqr2)
          ELSE IF(nbondi.eq.1) THEN
              CALL mppsend(1,t3ew_my1(1,1,1,1,1),imigr,nowe,0,reqs1)
              CALL mpprecv(2,t3we_my1(1,1,1,1,2),imigr,reqr1)
              CALL mppwait(reqs1)
              CALL mppwait(reqr1)
          ENDIF
!!

         ENDIF
!!
!!5.3 Write Dirichlet lateral conditions
!!

!!!!!$omp   parallel default(none) private(jn,jl,jk,jj,mytid,iihom)
!!!!!$omp&      shared(packsize,npolj,nbondi,nlci,jpreci,jpk,jpj,t3ew_my1,t3we_my1,ptab)
#ifdef __OPENMP11
        mytid = omp_get_thread_num()  ! take the thread ID
        jn=1
        IF(mytid +1 <= packsize) THEN
#else
      PACK_LOOP10: DO jn=1,packsize
#endif
          IF (npolj.eq.3.or.npolj.eq.4) THEN
          iihom=nlci-jpreci
          IF(nbondi.eq.0.or.nbondi.eq.1) THEN
!!
              DO jl=1,jpreci
                DO jk=1,jpk
                  DO jj=1,jpj
                    ptab(jl,jj,jk,jn+mytid)=t3we_my1(jk,jj,jl,jn+mytid,2)
                  END DO
                END DO
              END DO
          ENDIF
!!
          IF(nbondi.eq.-1.or.nbondi.eq.0) THEN
              DO jl=1,jpreci
                DO jk=1,jpk
                  DO jj=1,jpj
                    ptab(jj,iihom+jl,jk,jn+mytid)=t3ew_my1(jk,jj,jl,jn+mytid,2)
                  END DO
                END DO
              END DO
          ENDIF
      ENDIF
#ifdef __OPENMP11
      END IF
!!!!!$omp    end parallel
#else
      END DO PACK_LOOP10
#endif

#  else
!!
!!     No mpp computation
!!
#endif
!!
!!
      RETURN

END SUBROUTINE


     
!!!---------------------------------------------------------------------
!!!
!!!                       routine mpplnk2
!!!                     *******************
!!!
!!!  Purpose :
!!!  ---------
!!!      Message passing manadgement for 2d array
!!!
!!   Method :
!!   -------
!!       Use mppsend and mpprecv function for passing mask between
!!       processors following neighboring subdomains.
!!
!!   Input :
!!   -----
!!      argument
!!              ptab            : variable array
!!              ktype           : define the nature of the grid-point
!!                                at which ptab is defined for 0
!!                                initialization
!!                                initialization
!!                                = 1 ,  T- and W-points
!!                                = 2 ,  U-point
!!                                = 3 ,  V-point
!!                                = 4 ,  F-point
!!                                = 11,  T-point only fold treatment
!!                                = 14,  F-point only fold treatment
!!              ksgn            : control of the sign change
!!                                = 0 , the sign is modified following
!!                                the type of b.c. used
!!                                = 1 , the sign of the field is un-
!!                                changed at the boundaries
!!      common
!!            /COMDOM/ : domain parameters
!!                    nlci   : first dimension of the local subdomain
!!                    nlcj   : second dimension of the local subdomain
!!                    nbondi : mark for "east-west local boundary"
!!                    nbondj : mark for "north-south local boundary"
!!                    noea   : number for local neighboring processors
!!                    nowe   : number for local neighboring processors
!!                    noso   : number for local neighboring processors
!!                    nono   : number for local neighboring processors
!!            /COMMPP/ : massively parallel processors
!!                    t2ew() : message passing arrays east-west
!!                    t2we() : message passing arrays west-east
!!                    t2ns() : message passing arrays north-south
!!                    t2sn() : message passing arrays south-north
!!
!!   Output :
!!   ------
!!      common
!!            /COMMPP/ : massively parallel processors
!!                    t2ew() : message passing arrays east-west
!!                    t2we() : message passing arrays west-east
!!                    t2ns() : message passing arrays north-south
!!                    t2sn() : message passing arrays south-north
!!   Workspace :
!!   ---------
!!      local
!!             jj,ji,jl,imigr,iihom,ijhom
!!
!!   External :
!!   --------
!!             mppsend,mpprecv
!!       or    shmem_put barrier shmem_udcflush
!!
!!   References :                 no
!!   ----------
!!
!!   Modifications:
!!   --------------
!!       original  : 94-11 (M. Guyon)
!!       additions : 95-04 (j. Escobar, M. Imbard)
!!       additions : 98-05 (M. Imbard, J. Escobar, L. Colombet )
!!                          SHMEM and MPI versions
!!----------------------------------------------------------------------
 SUBROUTINE mpplnk2(ptab,ktype,ksgn)


!!----------------------------------------------------------------------
!!
      INTEGER ktype, ksgn
      double precision ptab(jpi,jpj)
      double precision t2p1(jpi,1,2)
      double precision t2p2(jpi,1,2)
#ifdef key_mpp_mpi

      INTEGER jj,ji,jl
      INTEGER imigr,iihom,ijhom,iloc,ijt,iju
      double precision zsgn
      INTEGER reqs1, reqs2, reqr1, reqr2
!!
!!!---------------------------------------------------------------------
!!!  OPA8, LODY!!(15/11/96)
!!!---------------------------------------------------------------------
!!
!!0. Initialization
!!-----------------
!!
!!Sign setting
!!...
      IF (ksgn.EQ.0) THEN
          zsgn = -1.
      ELSE
          zsgn =  1.
      ENDIF
!!
!!1. standard boundary treatment
!!------------------------------
!!
!!East-West boundary conditions
!!
      IF(nbondi.EQ.2.AND.(nperio.EQ.1.or.nperio.EQ.4)) THEN
!!... cyclic

          DO jj = 1, jpj
            ptab( 1 ,jj) = ptab(jpim1,jj)
            ptab(jpi,jj) = ptab(  2  ,jj)
          END DO
      ELSE
!!... closed
          IF( ktype .NE. 11 .and. ktype .NE. 14 ) Then
              iihom = nlci-jpreci
              DO ji = iihom+1,jpi
                DO jj = 1,jpj
                  ptab(jj,ji) = 0.e0
                END DO
              END DO
              IF ( ktype.NE.4  ) THEN
                  DO ji = 1,jpreci
                    DO jj = 1,jpj
                      ptab(jj,ji) = 0.e0
                    END DO
                  END DO
              ENDIF
          ENDIF
      ENDIF
!!
!!North-South boundary conditions
!!
      IF( ktype .NE. 11 .and. ktype .NE. 14 ) THEN
          ijhom = nlcj-jprecj
          DO jj = ijhom+1,jpj
            DO ji = 1,jpi
              ptab(jj,ji) = 0.e0
            END DO
          END DO
          IF ( ktype.NE.4 ) THEN
              DO jj = 1,jprecj
                DO ji = 1, jpi
                  ptab(jj,ji) = 0.e0
                END DO
              END DO
          ENDIF
      ENDIF
!!
!!
!!2. East and west directions
!!---------------------------
!!
!!2.1 Read Dirichlet lateral conditions
!!
      IF(nbondi.ne.2) THEN
          iihom=nlci-nreci
!!
          DO jl=1,jpreci
            DO jj=1,jpj
              t2ew(1,jj,jl)=ptab(jj,jpreci+jl)
              t2we(1,jj,jl)=ptab(jj,iihom+jl)
            END DO
          END DO
      ENDIF
!!
!!2.2 Migrations
!!
!!
      imigr=jpreci*jpj
!!
      IF(nbondi.eq.-1) THEN
          CALL mppsend(2,t2we(1,1,1),imigr,noea,0,reqs1)
          CALL mpprecv(1,t2ew(1,1,2),imigr,reqr1)
          CALL mppwait(reqs1)
          CALL mppwait(reqr1)
      ELSE IF(nbondi.eq.0) THEN
          CALL mppsend(1,t2ew(1,1,1),imigr,nowe,0,reqs1)
          CALL mppsend(2,t2we(1,1,1),imigr,noea,0,reqs2)
          CALL mpprecv(1,t2ew(1,1,2),imigr,reqr1)
          CALL mpprecv(2,t2we(1,1,2),imigr,reqr2)
          CALL mppwait(reqs1)
          CALL mppwait(reqs2)
          CALL mppwait(reqr1)
          CALL mppwait(reqr2)
      ELSE IF(nbondi.eq.1) THEN
          CALL mppsend(1,t2ew(1,1,1),imigr,nowe,0,reqs1)
          CALL mpprecv(2,t2we(1,1,2),imigr,reqr1)
          CALL mppwait(reqs1)
          CALL mppwait(reqr1)
      ENDIF
!!
!!
!!2.3 Write Dirichlet lateral conditions
!!
      iihom=nlci-jpreci
      IF(nbondi.eq.0.or.nbondi.eq.1) THEN
!!
          DO jl=1,jpreci
            DO jj=1,jpj
              ptab(jl,jj)=t2we(2,jj,jl)
            END DO
          END DO
      ENDIF
!!
      IF(nbondi.eq.-1.or.nbondi.eq.0) THEN
          DO jl=1,jpreci
            DO jj=1,jpj
              ptab(jj,iihom+jl)=t2ew(2,jj,jl)
            END DO
          END DO
      ENDIF
!!
!!
!!3. North and south directions
!!-----------------------------
!!
!!3.1 Read Dirichlet lateral conditions
!!
      IF(nbondj.ne.2) THEN
          ijhom=nlcj-nrecj
!!
          DO jl=1,jprecj
            DO ji=1,jpi
              t2sn(1,jl,ji)=ptab(ijhom +jl,ji)
              t2ns(1,jl,ji)=ptab(jprecj+jl,ji)
            END DO
          END DO
      ENDIF
!!
!!3.2 Migrations
!!
!!
!!MPI VERSION
!!
      imigr=jprecj*jpi
!!
      IF(nbondj.eq.-1) THEN
          CALL mppsend(4,t2sn(1,1,1),imigr,nono,0,reqs1)
          CALL mpprecv(3,t2ns(1,1,2),imigr,reqr1)
          CALL mppwait(reqs1)
          CALL mppwait(reqr1)
      ELSE IF(nbondj.eq.0) THEN
          CALL mppsend(3,t2ns(1,1,1),imigr,noso,0,reqs1)
          CALL mppsend(4,t2sn(1,1,1),imigr,nono,0,reqs2)
          CALL mpprecv(3,t2ns(1,1,2),imigr,reqr1)
          CALL mpprecv(4,t2sn(1,1,2),imigr,reqr2)
          CALL mppwait(reqs1)
          CALL mppwait(reqs2)
          CALL mppwait(reqr1)
          CALL mppwait(reqr2)
      ELSE IF(nbondj.eq.1) THEN
          CALL mppsend(3,t2ns(1,1,1),imigr,noso,0,reqs1)
          CALL mpprecv(4,t2sn(1,1,2),imigr,reqr1)
          CALL mppwait(reqs1)
          CALL mppwait(reqr1)
      ENDIF
!!
!!
!!3.3 Write Dirichlet lateral conditions
!!
      ijhom=nlcj-jprecj
      IF(nbondj.eq.0.or.nbondj.eq.1) THEN
          DO jl=1,jprecj
            DO ji=1,jpi
              ptab(ji,jl)=t2sn(2,jl,ji)
            END DO
          END DO
      ENDIF
!!
      IF(nbondj.eq.0.or.nbondj.eq.-1) THEN
          DO jl=1,jprecj
            DO ji=1,jpi
              ptab(ji,ijhom+jl)=t2ns(2,jl,ji)
            END DO
          END DO
      ENDIF
!!
!!4. north fold treatment
!!-----------------------
!!
!!4.1 treatment without exchange (jpni odd)
!!
      IF (npolj.eq.4) THEN
          iloc=jpiglo-2*(nimpp-1)
          IF ( ktype.EQ.1 .OR. ktype.EQ.11 ) THEN
              DO ji = 2, nlci
                ijt=iloc-ji+2
                ptab(ji,nlcj) = zsgn * ptab(ijt,nlcj-2)
              END DO
              DO ji = nlci/2+1, nlci
                ijt=iloc-ji+2
                ptab(ji,nlcj-1) = zsgn * ptab(ijt,nlcj-1)
              END DO
          ELSEIF ( ktype.EQ.2 ) THEN
              DO ji = 1, nlci-1
                iju=iloc-ji+1
                ptab(ji,nlcj) = zsgn * ptab(iju,nlcj-2)
              END DO
              DO ji = nlci/2, nlci-1
                iju=iloc-ji+1
                ptab(ji,nlcj-1) = zsgn * ptab(iju,nlcj-1)
              END DO
          ELSEIF ( ktype.EQ.3 ) THEN
              DO ji = 2, nlci
                ijt=iloc-ji+2
                ptab(ji,nlcj-1) = zsgn * ptab(ijt,nlcj-2)
                ptab(ji,nlcj  ) = zsgn * ptab(ijt,nlcj-3)
              END DO
          ELSEIF ( ktype.EQ.4 .OR. ktype.EQ.14 ) THEN
              DO ji = 1, nlci-1
                iju=iloc-ji+1
                ptab(ji,nlcj-1) = ptab(iju,nlcj-2)
                ptab(ji,nlcj  ) = ptab(iju,nlcj-3)
              END DO
          ENDIF
      ENDIF
!!
!!4.1 treatment with exchange (jpni greater than 1)
!!
!!... sign and sort are taken into a!!ount in the sender processor
!!
      IF (npolj.eq.3) THEN
          iloc=jpiglo-(nimpp-1+nimppt(nono+1)-1)
          IF ( ktype.EQ.1 .OR. ktype.EQ.11 ) THEN
              DO ji=2,jpi
                ijt=iloc-ji+2
                if(ijt .ge. 1) then
                   t2p1(ji,1,1) = zsgn * ptab(ijt,nlcj-2)
                   t2p2(ji,1,1) = zsgn * ptab(ijt,nlcj-1)
                else
                   t2p1(ji,1,1) = zsgn * ptab(ijt+jpi,nlcj-2-1)
                   t2p2(ji,1,1) = zsgn * ptab(ijt+jpi,nlcj-1-1)
                endif
              END DO
          ELSEIF ( ktype.EQ.2 ) THEN
              DO ji = 1, jpi-1
                iju=iloc-ji+1
                if(iju .ge. 1) then
                   t2p1(ji,1,1) = zsgn * ptab(iju,nlcj-2)
                   t2p2(ji,1,1) = zsgn * ptab(iju,nlcj-1)
                else
                   t2p1(ji,1,1) = zsgn * ptab(iju+jpi,nlcj-2-1)
                   t2p2(ji,1,1) = zsgn * ptab(iju+jpi,nlcj-1-1)
                endif
              END DO
          ELSEIF ( ktype.EQ.3 ) THEN
              DO ji = 2, jpi
                ijt=iloc-ji+2
                if(ijt .ge. 1) then
                   t2p1(ji,1,1) = zsgn * ptab(ijt,nlcj-2)
                   t2p2(ji,1,1) = zsgn * ptab(ijt,nlcj-3)
                else
                   t2p1(ji,1,1) = zsgn * ptab(ijt+jpi,nlcj-2-1)
                   t2p2(ji,1,1) = zsgn * ptab(ijt+jpi,nlcj-3-1)
                endif
              END DO
          ELSEIF ( ktype.EQ.4 .OR. ktype.EQ.14 ) THEN
              DO ji = 1, jpi-1
                iju=iloc-ji+1
                if(iju .ge. 1) then
                   t2p1(ji,1,1) = ptab(iju,nlcj-2)
                   t2p2(ji,1,1) = ptab(iju,nlcj-3)
                else
                   t2p1(ji,1,1) = ptab(iju+jpi,nlcj-2-1)
                   t2p2(ji,1,1) = ptab(iju+jpi,nlcj-3-1)
                endif
              END DO
          ENDIF
!!
!!4.2 Migrations
!!
!!
!!MPI VERSION
!!
          imigr=jprecj*jpi
!!
          CALL mppsend(3,t2p1(1,1,1),imigr,nono,0,reqs1)
          CALL mpprecv(3,t2p1(1,1,2),imigr,reqr1)
          CALL mppwait(reqs1)
          CALL mppwait(reqr1)
          CALL mppsend(4,t2p2(1,1,1),imigr,nono,0,reqs2)
          CALL mpprecv(4,t2p2(1,1,2),imigr,reqr2)
          CALL mppwait(reqs2)
          CALL mppwait(reqr2)
!!
!!
!!4.3 Write north fold conditions
!!
          IF ( ktype .EQ. 1 .or. ktype .eq. 11 ) THEN
              DO ji = 2, nlci
                ptab(ji,nlcj) = t2p1(ji,1,2)
              END DO
              IF(nimpp+nlcj/2 .gt. jpjglo/2) THEN
                  DO ji = 2, nlci
                    ptab(ji,nlcj-1) = t2p2(ji,1,2)
                  END DO
              ENDIF
          ELSEIF ( ktype.EQ.2 ) THEN
              DO ji = 1, nlci-1
                ptab(ji,nlcj) = t2p1(ji,1,2)
              END DO
              IF(nimpp+nlcj/2 .gt. jpjglo/2) THEN
                  DO ji = 1, nlci-1
                    ptab(ji,nlcj-1) = t2p2(ji,1,2)
                  END DO
              ENDIF
          ELSEIF ( ktype .EQ.3 ) THEN
              DO ji = 2, nlci
                ptab(ji,nlcj-1) = t2p1(ji,1,2)
                ptab(ji,nlcj  ) = t2p2(ji,1,2)
              END DO
          ELSEIF ( ktype .EQ.4 .or. ktype .EQ.14 ) THEN
              DO ji = 1, nlci-1
                ptab(ji,nlcj-1) = t2p1(ji,1,2)
                ptab(ji,nlcj  ) = t2p2(ji,1,2)
              END DO
          ENDIF
      ENDIF
!!
!!
!!5. East and west directions
!!---------------------------
!!
      IF (npolj.eq.3.or.npolj.eq.4) THEN
!!
!!5.1 Read Dirichlet lateral conditions
!!
          IF(nbondi.ne.2) THEN
              iihom=nlci-nreci
!!
              DO jl=1,jpreci
                DO jj=1,jpj
                  t2ew(1,jj,jl)=ptab(jj,jpreci+jl)
                  t2we(1,jj,jl)=ptab(jj,iihom+jl)
                END DO
              END DO
          ENDIF
!!
!!5.2 Migrations
!!
!!
!!MPI VERSION
!!
          imigr=jpreci*jpj
!!
          IF(nbondi.eq.-1) THEN
              CALL mppsend(2,t2we(1,1,1),imigr,noea,0,reqs1)
              CALL mpprecv(1,t2ew(1,1,2),imigr,reqr1)
              CALL mppwait(reqs1)
              CALL mppwait(reqr1)
          ELSE IF(nbondi.eq.0) THEN
              CALL mppsend(1,t2ew(1,1,1),imigr,nowe,0,reqs1)
              CALL mppsend(2,t2we(1,1,1),imigr,noea,0,reqs2)
              CALL mpprecv(1,t2ew(1,1,2),imigr,reqr1)
              CALL mpprecv(2,t2we(1,1,2),imigr,reqr2)
              CALL mppwait(reqs1)
              CALL mppwait(reqs2)
              CALL mppwait(reqr1)
              CALL mppwait(reqr2)
          ELSE IF(nbondi.eq.1) THEN
              CALL mppsend(1,t2ew(1,1,1),imigr,nowe,0,reqs1)
              CALL mpprecv(2,t2we(1,1,2),imigr,reqr1)
              CALL mppwait(reqs1)
              CALL mppwait(reqr1)
          ENDIF
!!
!!
!!5.3 Write Dirichlet lateral conditions
!!
          iihom=nlci-jpreci
          IF(nbondi.eq.0.or.nbondi.eq.1) THEN
!!
              DO jl=1,jpreci
                DO jj=1,jpj
                  ptab(jl,jj)=t2we(2,jj,jl)
                END DO
              END DO
          ENDIF
!!
          IF(nbondi.eq.-1.or.nbondi.eq.0) THEN
              DO jl=1,jpreci
                DO jj=1,jpj
                  ptab(jj,iihom+jl)=t2ew(2,jj,jl)
                END DO
              END DO
          ENDIF
      ENDIF
#  else
!!
!!     No mpp computation
!!
#endif

      RETURN

END SUBROUTINE



!!!---------------------------------------------------------------------
!!!
!!!                       routine mppsend
!!!                     *******************
!!!
!!!  Purpose :
!!!  ---------
!!!     Send messag passing array
!!
!!   Input :
!!   -----
!!      argument                :
!!                   ktyp   -> Tag of the message
!!                   pmess  -> array of double precision to send
!!                   kbytes -> size of pmess in double precision
!!                   kdest  -> receive process number
!!                   kid    _> ? (note used)
!!
!!   Modifications:
!!   --------------
!!       original  : 93-09 (M. Imbard)
!!       additions : 96-05 (j. Escobar)
!!       additions : 98-05 (M. Imbard, J. Escobar, L. Colombet )
!!                          SHMEM and MPI versions
!!----------------------------------------------------------------------

SUBROUTINE mppsend(ktyp,pmess,kbytes,kdest,kid,ireqsend)


      double precision pmess(*)
      INTEGER kbytes,kdest,ktyp,kid, ireqsend

#ifdef key_mpp_mpi





      INTEGER iflag
      CALL mpi_isend(pmess,kbytes,mpi_real8,kdest,ktyp, &
     &    mpi_comm_world,ireqsend,iflag)


#endif
      RETURN

END SUBROUTINE

!!!---------------------------------------------------------------------
!!!
!!!                       routine mpprecv
!!!                     *******************
!!!
!!!  Purpose :
!!!  ---------
!!!     Receive messag passing array
!!
!!   Input :
!!   -----
!!      argument
!!                   ktyp    -> Tag of the recevied message
!!                   pmess   -> array of double precision
!!                   kbytes  -> suze of the array pmess


!!
!!   Modifications:
!!   --------------
!!       original  : 93-09 (M. Imbard)
!!       additions : 96-05 (j. Escobar)
!!       additions : 98-05 (M. Imbard, J. Escobar, L. Colombet )
!!                          SHMEM and MPI versions
!!----------------------------------------------------------------------

 SUBROUTINE mpprecv(ktyp,pmess,kbytes,ireqrecv)

      double precision pmess(*)
      INTEGER   kbytes,ktyp, ireqrecv

#ifdef key_mpp_mpi

      INTEGER iflag

      CALL mpi_irecv(pmess,kbytes,mpi_real8,mpi_any_source,ktyp,mpi_comm_world,ireqrecv,iflag)
#endif

      RETURN

END SUBROUTINE

!!!---------------------------------------------------------------------
!!!
!!!                       routine mppwait
!!!                     *******************
!!!
!!!  Purpose :
!!!  ---------
!!!     Wait message passing isend/irecv
!!
!!   Input :
!!   -----
!!      argument
!!----------------------------------------------------------------------
SUBROUTINE mppwait(req)
      INTEGER istatus(mpi_status_size), ierr
      integer req
      


#ifdef key_mpp_mpi
      call MPI_WAIT(req, istatus, ierr)
#endif
      RETURN
END SUBROUTINE

!!!---------------------------------------------------------------------
!!!
!!!                       routine mppsync
!!!                     *******************
!!!
!!!  Purpose :
!!!  ---------
!!!     Massively parallel processors, synchroneous
!!
!!   Modifications:
!!   --------------
!!       original  : 93-09 (M. Imbard)
!!       additions : 96-05 (j. Escobar)
!!       additions : 98-05 (M. Imbard, J. Escobar, L. Colombet )
!!                          SHMEM and MPI versions
!!----------------------------------------------------------------------
SUBROUTINE mppsync()

!!----------------------------------------------------------------------

#ifdef key_mpp_mpi

      INTEGER ierror

      CALL mpi_barrier(mpi_comm_world,ierror)

#endif
      RETURN
END SUBROUTINE

SUBROUTINE mppstop
!!!---------------------------------------------------------------------
!!!
!!!                       routine mppstop
!!!                     *******************
!!!
!!!  purpose :
!!!  --------
!!!     Stop massilively parallel processors method
!!


      INTEGER info

#ifdef key_mpp_mpi
      CALL mppsync
#endif

      RETURN
END SUBROUTINE

END MODULE ogstm_mpi_module
