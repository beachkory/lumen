!
!        Copyright (C) 2000-2016 the YAMBO team
!              http://www.yambo-code.org
!
! Authors (see AUTHORS file for details): MG, CA, DS
!
! This file is distributed under the terms of the GNU 
! General Public License. You can redistribute it and/or 
! modify it under the terms of the GNU General Public 
! License as published by the Free Software Foundation; 
! either version 2, or (at your option) any later version.
!
! This program is distributed in the hope that it will 
! be useful, but WITHOUT ANY WARRANTY; without even the 
! implied warranty of MERCHANTABILITY or FITNESS FOR A 
! PARTICULAR PURPOSE.  See the GNU General Public License 
! for more details.
!
! You should have received a copy of the GNU General Public 
! License along with this program; if not, write to the Free 
! Software Foundation, Inc., 59 Temple Place - Suite 330,Boston, 
! MA 02111-1307, USA or visit http://www.gnu.org/copyleft/gpl.txt.
!
subroutine DIPOLE_build_covariants(Xen,Xk,X)
 !
 ! Build the covariant dipole operator at zero field
 ! in PRB 69, 085106 (2004)
 !
 use pars,           ONLY:SP,cI,cZERO,pi
 use LIVE_t,         ONLY:live_timing
 use interfaces,     ONLY:WF_load,PARALLEL_WF_distribute
 use wave_func,      ONLY:WF
 use electrons,      ONLY:levels,n_sp_pol
 use X_m,            ONLY:X_t,DIP_S,DIP_iR,DIP_P,X_alloc,force_v_g_space_approach
 use R_lattice,      ONLY:bz_samp,k_map
 use vec_operate,    ONLY:k_periodic_idx
 use matrix_operate, ONLY:hermitian
 use parallel_m,     ONLY:PAR_IND_DIPk_ibz,PAR_DIPk_ibz_index,PAR_IND_Xk_ibz_ID, &
&                         PAR_IND_OVLP_ibz,PAR_Xk_nbz,PAR_COM_DIPOLES,PP_redux_wait
 use com,            ONLY:error,warning,msg
 use D_lattice,      ONLY:a
 use parser_m,       ONLY:parser
 use parallel_m,     ONLY:master_cpu
 use IO_m,           ONLY:io_control,VERIFY,REP,OP_WR_CL,OP_APP_WR_CL,OP_RD_CL

 !
 implicit none
 !
 type(levels),           intent(in)     :: Xen
 type(bz_samp),          intent(in)     :: Xk
 type(X_t),              intent(in)     :: X      
 !
 ! Work Space
 !
 logical     :: idir_not_done(3)
 logical     :: l_eval_polarization,l_force_SndOrd
 integer     :: ik,iv,ic,i_sp_pol,ikm1,id_red,idir,idx(3),i1,i2,ikbz,ik_mem
 integer     :: istep,max_step
 real(SP)    :: Ev_m_Ec
 complex(SP) :: Sm1_plus (Xen%nbm,Xen%nbm,6)
 complex(SP) :: Sm1_minus(Xen%nbm,Xen%nbm,6)
 complex(SP) :: S_det(6)
 complex(SP) :: Wop(1:X%ib(2),1:X%ib(2),2),DIP_tmp(6,1:X%ib(2),1:X%ib(2))
 complex(SP) :: S_tmp(X%ib(2),X%ib(2),2)
 logical     :: l_mat_eval_DIP(X%ib_lim(2):X%ib(2),X%ib(1):X%ib_lim(1))
 integer     :: n_LT_steps
 !
 integer           :: io_err,ID
 integer, external :: io_Overlaps
 !
 if (Xen%nbf/=Xen%nbm) call error(' Covariant dipoles not implemented for metals')
 !
 call parser('EvPolarization'  ,l_eval_polarization)
 call parser('FrSndOrd'        ,l_force_SndOrd)
 !
 ! WF load 
 ! Here I avoid the deallocation of states_to_load as I ASSUME that AFTER this routine 
 ! there will be other WF_load calls using the present WF distribution. 
 ! I force the system to load all the WF distribution not implemented yet
 !
 call k_map_nearest_by_dir(Xk,k_map)
 !
 call k_build_up_BZ_tables(Xk)
 !
 call DIPOLE_build_parallelization_mask(X,l_mat_eval_DIP,n_LT_steps)
 !
 call PARALLEL_WF_distribute(K_index=PAR_IND_OVLP_ibz,CLEAN_UP=.TRUE.)
 !
 call WF_load(WF,0,1,(/1,X%ib(2)/),(/1,Xk%nibz/),space='G',title='-Oscillators/G space',&
 &             keep_states_to_load=.TRUE.)
 !
 ! In the covariat approach I do need the overlap. 
 ! So as a first thing I check if they exist
 !
 ! If they do not I have to compute them
 !
 call io_control(ACTION=OP_RD_CL,COM=REP,SEC=(/1/),MODE=VERIFY,ID=ID)
 io_err=io_Overlaps(X,ID)
 !
 if(io_err/=0) then
   !
   ! Notice that DIP_S is defined in the BZ       
   !
   call X_alloc('DIP_S',(/X%ib(2),X%ib(2),6,PAR_Xk_nbz/))
   DIP_S=cZERO
   !
   call DIPOLE_overlaps(Xk,X)
   !
 else
   !
   ! Overlaps already calculated, just load them
   !
   do ik=1,Xk%nbz
     do i_sp_pol=1,n_sp_pol
       call io_control(ACTION=OP_RD_CL,COM=REP,SEC=(/1+ik+(i_sp_pol-1)*Xk%nbz/),ID=ID)
       io_err=io_err+io_Overlaps(X,ID)
     enddo
   enddo
   !
 endif
 !
 idir_not_done(:)= (k_map%max_kdir(:)==1)
 !
 if(any(idir_not_done)) call warning(' Covariant Dipoles not in 3d. Assuming non periodic system.')
 !
 if(any(k_map%max_kdir(:)>=6.and..not.l_force_SndOrd)) &
 &   call msg('rs','Using forth order approximation for covariant dipoles')
 !
 call live_timing('Covariant Dipoles:',PAR_IND_DIPk_ibz%n_of_elements(PAR_IND_Xk_ibz_ID+1)*n_sp_pol)
 !
 ! Notice that DIP_iR/DIP_P are defined only in the IBZ
 ! while the overlaps are in the BZ 
 !
 do i_sp_pol=1,n_sp_pol
   !
   do ik=1,Xk%nibz 
     !
     if (.not.PAR_IND_DIPk_ibz%element_1D(ik)) cycle
     !
     ik_mem=PAR_DIPk_ibz_index(ik)
     !
     ikbz=Xk%k_table(ik,1)
     !
     call Build_Overlaps_Det_EQ(Xen,i_sp_pol,ikbz,Sm1_plus,Sm1_minus,S_det)
     !
     DIP_tmp=cZERO
     !
     do id_red=1,3  ! loop on reciprocal lattice
       !
       if(k_map%max_kdir(id_red)==1) cycle
       !
       max_step=1
       !
       ! I need at leat 5 k-points in the line to
       ! use the second order formula
       !
       if(k_map%max_kdir(id_red)>=6.and..not.l_force_SndOrd) max_step=2
       !
       do istep=1,max_step 
         !
         idx=k_map%k_map_inv(ikbz,:)
         idx(id_red)=idx(id_red)-istep
         idx=k_periodic_idx(idx,k_map)
         ikm1=k_map%k_map_dir(idx(1),idx(2),idx(3))
         !
         S_tmp(:,:,1)=          DIP_S(:,:,id_red+(istep-1)*3,ikbz,i_sp_pol)
         S_tmp(:,:,2)=hermitian(DIP_S(:,:,id_red+(istep-1)*3,ikm1,i_sp_pol))
         !
         Wop(:,:,istep)=cZERO
         !
         forall(i1=Xen%nbm+1:X%ib(2),i2=1:Xen%nbf) 
           Wop(i1,i2,istep)=sum(S_tmp(i1,1:Xen%nbf,1)* Sm1_plus(1:Xen%nbf,i2,id_red + (istep-1)*3))- &
&                           sum(S_tmp(i1,1:Xen%nbf,2)*Sm1_minus(1:Xen%nbf,i2,id_red + (istep-1)*3))
         end forall
         !
         Wop(:,:,istep)=Wop(:,:,istep)*cI*k_map%max_kdir(id_red)/(4._SP*pi*real(istep,SP))
         !
       enddo ! istep
       !
       ! Transform in cartesian coordinates 
       !
       if(max_step==1) then 
         !      
         ! First order formula D(dk)      
         ! Eq. 96 of PRB 63, 155107(2001)
         !
         do idir=1,3
           DIP_tmp(idir,:,:)=DIP_tmp(idir,:,:)+transpose(Wop(:,:,1))*a(id_red,idir)
         enddo
         !
        else
          !      
          ! Second order formula   ( 4*D(dk) - D(2*dk) ) / 3
          ! Eq. 97 of PRB 63, 155107(2001)
          !
          do idir=1,3
            DIP_tmp(idir,:,:)=DIP_tmp(idir,:,:)+transpose(4._SP*Wop(:,:,1)-Wop(:,:,2))/3._SP*a(id_red,idir)
          enddo
        endif
        !
      enddo ! id_red
      !
      !======
      ! <iR>
      !======
      do iv=X%ib(1),X%ib_lim(1)
        do ic=max(iv,X%ib_lim(2)),X%ib(2)
          !
          if (.not.l_mat_eval_DIP(ic,iv)) cycle
          !
          do idir=1,3
            DIP_iR(idir,ic,iv,ik_mem,i_sp_pol)=(DIP_tmp(idir,ic,iv)+conjg(DIP_tmp(idir,iv,ic)))/cI
          enddo
          !
        enddo
      enddo
      !
      !=====
      ! <P>
      !=====
      if(.not.force_v_g_space_approach) then
        !      
        do iv=X%ib(1),X%ib_lim(1) 
          do ic=max(iv,X%ib_lim(2)),X%ib(2)
            !
            if (.not.l_mat_eval_DIP(ic,iv)) cycle
            !
            ! This is directly p_eff, see Dipole transverse and PRB 48, 11789 (1993)
            Ev_m_Ec=Xen%E(iv,ik,i_sp_pol)-Xen%E(ic,ik,i_sp_pol)
            !
            do idir=1,3
             DIP_P(idir,ic,iv,ik_mem,i_sp_pol)=DIP_iR(idir,ic,iv,ik_mem,i_sp_pol)*Ev_m_Ec
           enddo
           !
         enddo
       enddo
       !
     endif
     !
     call live_timing(steps=1)
     !
   enddo ! ik
 enddo ! i_sp_pol
 !
 call live_timing()
 !
 if(l_eval_polarization) call POLARIZATION_output(Xen,Xk,X)     
 !
 call WF_free(WF)
 !
 call PARALLEL_WF_distribute(K_index=PAR_IND_DIPk_ibz,CLEAN_UP=.TRUE.)
 !
 return
 !
end subroutine DIPOLE_build_covariants
