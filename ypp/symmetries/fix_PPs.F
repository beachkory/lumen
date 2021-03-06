!
!        Copyright (C) 2000-2016 the YAMBO team
!              http://www.yambo-code.org
!
! Authors (see AUTHORS file for details): CA DS
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
subroutine fix_PPs(E,k,k_save,kpoints_map,old_nsym,old_dl_sop,old_sop_inv,S_contains_TR,action_kind)
 !
 use pars,                ONLY:SP,lchlen
 use com,                 ONLY:msg,core_io_path,more_io_path
 use memory_m,            ONLY:mem_est
 use IO_m,                ONLY:io_control,OP_WR_CL,NONE,OP_APP_WR_CL,OP_WR,OP_RD,VERIFY,&
&                              OP_APP,cp_file,OP_RD_CL,RD_CL,RD,DUMP
 use electrons,           ONLY:n_spin,n_sp_pol
 use pseudo,              ONLY:pp_kb,pp_kbd,pp_kbs,n_atomic_species,PP_alloc_pwscf,&
&                              pp_n_l_times_proj_max,PP_free,PP_alloc_abinit,Vnl
 use LIVE_t,              ONLY:live_timing
 use X_m,                 ONLY:X_t
 use stderr,              ONLY:intc
 use wave_func,           ONLY:wf_ng,wf_ncx
 use R_lattice,           ONLY:bz_samp,ng_closed,g_rot,nXkibz,ng_vec
 use D_lattice,           ONLY:n_atomic_species
 use electrons,           ONLY:levels
 use YPP_symm
 !
 implicit none
 !
 type(levels),intent(in)  :: E
 !
 type(bz_samp),intent(in) :: k
 type(bz_samp),intent(in) :: k_save
 integer,intent(in)       :: kpoints_map(2,k%nibz)
 !
 integer,intent(in)       :: old_nsym
 real(SP),intent(in)      :: old_dl_sop(3,3,old_nsym)
 integer,intent(in)       :: old_sop_inv(old_nsym)
 logical,intent(in)       :: S_contains_TR(old_nsym)
 !
 integer,intent(in)       :: action_kind
 !
 ! Work space
 !
 type(X_t)             :: X_Vnl
 !
 character(lchlen)     :: core_io_path_save,fragment_name
 integer               :: n_steps,ID
 integer               :: ierr,io_KB_abinit_err,io_KB_pwscf_err,io_Vnl_err
 integer               :: ng_vec_tmp
 !
 real(SP),allocatable     :: pp_kb_store(:,:,:,:,:)
 real(SP),allocatable     :: pp_kbd_store(:,:,:,:,:)
 real(SP),allocatable     :: pp_kbs_store(:,:)
 complex(SP), allocatable :: Vnl_store(:,:,:,:,:)
 !
 ! Dummies
 !
 integer               :: is,ik,ik_save
 integer               :: ic,ic_rot,ig,ig_rot
 integer               :: ib,ibm,i_spin
 !
 ! External functions
 !
 integer, external :: io_KB_abinit
 integer, external :: io_KB_pwscf
 integer, external :: io_Vnl
 !
 ! Check the presence of PPs DBs
 !
 n_steps=k%nibz-k_save%nibz
 !
 io_Vnl_err     =-1
 io_KB_abinit_err=-1
 io_KB_pwscf_err =-1
 !
 ! PWscf (old)
 X_Vnl%ib=(/1,E%nb/)       ! full bands range
 X_Vnl%ngostnts=1          ! to overcome check for io
 nXkibz=k_save%nibz
 call io_control(ACTION=OP_RD_CL,COM=NONE,SEC=(/1/),MODE=VERIFY,ID=ID)
 io_Vnl_err=io_Vnl(X_Vnl,E,ID)
 !
 ! Check for the KB pwscf DB 
 if(.not.io_KB_abinit_err==0) then
   call io_control(ACTION=OP_RD,COM=NONE,SEC=(/1/),MODE=VERIFY,ID=ID)
   io_KB_pwscf_err=io_KB_pwscf(ID)
 endif
 !
 ! Check for the KB abinit DB 
 if(.not.io_KB_pwscf_err==0) then
   call io_control(ACTION=OP_RD,COM=NONE,SEC=(/1/),MODE=VERIFY,ID=ID)
   io_KB_abinit_err=io_KB_abinit(ID)
 endif
 !
 if(io_KB_abinit_err/=0.and.io_KB_pwscf_err/=0.and.io_Vnl_err/=0) return
 !
 if(io_KB_abinit_err==0)   call section('=',"PseudoPotentials KB (Abinit)")
 if(io_KB_pwscf_err ==0)   call section('=',"PseudoPotentials KB (PWscf) ")
 if(io_Vnl_err==0)         call section('=',"PseudoPotentials old (PWscf)")
 !
 ! Read PP DBs
 !
 if(io_KB_abinit_err==0) then
   !
   ng_vec_tmp=ng_vec
   ng_vec=ng_closed
   !
   call io_control(ACTION=OP_RD,COM=NONE,SEC=(/1/),MODE=DUMP,ID=ID)
   io_KB_abinit_err=io_KB_abinit(ID) 
   !  
   allocate(pp_kb_store(ng_closed,n_atomic_species,pp_n_l_times_proj_max,n_spin,k_save%nibz))
   allocate(pp_kbd_store(ng_closed,n_atomic_species,pp_n_l_times_proj_max,n_spin,k_save%nibz))
   allocate(pp_kbs_store(n_atomic_species,pp_n_l_times_proj_max))
   call mem_est("pp_kb_store pp_kbd_store",(/size(pp_kb),size(pp_kbd)/),elements_kind=(/SP,SP/))
   !
   do ik=1,k_save%nibz
     !
     if (ik< k_save%nibz) call io_control(ACTION=RD,SEC=(/ik+1/),ID=ID)
     if (ik==k_save%nibz) call io_control(ACTION=RD_CL,SEC=(/ik+1/),ID=ID)      
     io_KB_abinit_err=io_KB_abinit(ID)
     !
     pp_kb_store(:,:,:,:,ik) =pp_kb(:,:,:,:)
     pp_kbd_store(:,:,:,:,ik)=pp_kbd(:,:,:,:)
     !
   enddo
   !
   pp_kbs_store=pp_kbs
   !
   ng_vec=ng_vec_tmp
   !
 endif
 !
 if(io_KB_pwscf_err==0) then
   !
   wf_ncx=wf_ncx_save
   !
   call io_control(ACTION=OP_RD,COM=NONE,SEC=(/1/),MODE=DUMP,ID=ID)
   io_KB_pwscf_err=io_KB_pwscf(ID) 
   !  
   allocate(pp_kb_store(wf_ncx,n_atomic_species,pp_n_l_times_proj_max,1,k_save%nibz))
   allocate(pp_kbd_store(wf_ncx,n_atomic_species,pp_n_l_times_proj_max,1,k_save%nibz))
   allocate(pp_kbs_store(n_atomic_species,pp_n_l_times_proj_max))
   call mem_est("pp_kb_store pp_kbd_store",(/size(pp_kb),size(pp_kbd)/),elements_kind=(/SP,SP/))
   !
   do ik=1,k_save%nibz
     !
     if (ik< k_save%nibz) call io_control(ACTION=RD,SEC=(/ik+1/),ID=ID)
     if (ik==k_save%nibz) call io_control(ACTION=RD_CL,SEC=(/ik+1/),ID=ID)      
     io_KB_pwscf_err=io_KB_pwscf(ID)
     !
     pp_kb_store(:,:,:,:,ik) =pp_kb(:,:,:,:)
     pp_kbd_store(:,:,:,:,ik)=pp_kbd(:,:,:,:)
     !
   enddo
   !
   pp_kbs_store=pp_kbs
   !
   !ng_vec=ng_vec_save
   !
 endif
 !
 if(io_Vnl_err==0) then
   allocate( Vnl_store(3,E%nb,E%nbm,k_save%nibz,n_sp_pol) )
   Vnl_store=(0._SP,0._SP)
   call mem_est("Vnl_store",(/size(Vnl_store)/),elements_kind=(/SP/))
   !
   call io_control(ACTION=OP_RD_CL,SEC=(/1,2/),ID=ID)
   io_Vnl_err=io_Vnl(X_Vnl,E,ID)
   !
   Vnl_store=Vnl
   !
   deallocate(Vnl)
   !   
 endif
 !
 core_io_path_save=core_io_path
 core_io_path=more_io_path
 !
 select case(action_kind)
 case(1)
   !
   if(io_KB_abinit_err==0) then
     !
     call msg('s',':: Copying existing database ...')
     !
     call cp_file(trim(core_io_path_save)//"/SAVE/s.kb_pp",trim(more_io_path)//"/SAVE",ierr)
     call cp_file(trim(core_io_path_save)//"/SAVE/ns.kb_pp",trim(more_io_path)//"/SAVE",ierr)
     do ik=1,k_save%nibz
       fragment_name='ns.kb_pp_fragment_'//trim(intc(ik))
       call cp_file(trim(core_io_path_save)//"/SAVE/"//trim(fragment_name),trim(more_io_path)//"/SAVE/",ierr)
       fragment_name='s.kb_pp_fragment_'//trim(intc(ik))
       call cp_file(trim(core_io_path_save)//"/SAVE/"//trim(fragment_name),trim(more_io_path)//"/SAVE/",ierr)
     enddo
     !
     call msg('l','done')
     !
   endif
   !
   if(io_KB_pwscf_err==0) then
     !
     if (wf_ncx_save==wf_ncx_new) then
       !
       call msg('s',':: Copying existing database ...')
       !
       call cp_file(trim(core_io_path_save)//"/SAVE/s.kb_pp_pwscf",trim(more_io_path)//"/SAVE",ierr)
       call cp_file(trim(core_io_path_save)//"/SAVE/ns.kb_pp_pwscf",trim(more_io_path)//"/SAVE",ierr)
       do ik=1,k_save%nibz
         fragment_name='ns.kb_pp_pwscf_fragment_'//trim(intc(ik))
         call cp_file(trim(core_io_path_save)//"/SAVE/"//trim(fragment_name),trim(more_io_path)//"/SAVE/",ierr)
         fragment_name='s.kb_pp_pwscf_fragment_'//trim(intc(ik))
         call cp_file(trim(core_io_path_save)//"/SAVE/"//trim(fragment_name),trim(more_io_path)//"/SAVE/",ierr)
       enddo
       !
       call msg('l','done')
       !
     endif
     !
   endif
   !
   ! Pseudo-potentials
   !
   if(io_KB_abinit_err==0) then 
     !
     pp_kb=0._SP
     pp_kbd=0._SP
     !
     if(n_steps>0) call live_timing('PPs rotation',n_steps)
     !
     do ik=k_save%nibz+1,k%nibz
       !
       ik_save=kpoints_map(1,ik)
       is=kpoints_map(2,ik)
       !
       pp_kb(1:ng_closed,:,:,:) =pp_kb_store(g_rot(old_sop_inv(is),1:ng_closed),:,:,:,ik_save)
       pp_kbd(1:ng_closed,:,:,:)=pp_kbd_store(g_rot(old_sop_inv(is),1:ng_closed),:,:,:,ik_save)
       !
       call io_control(ACTION=OP_APP_WR_CL,COM=NONE,SEC=(/ik+1/),ID=ID)      
       io_KB_abinit_err=io_KB_abinit(ID)
       !
       call live_timing(steps=1)
       !
     enddo
     !
     deallocate(pp_kb_store,pp_kbd_store,pp_kbs_store)
     call mem_est("pp_kb_store pp_kbd_store")
     !
     call PP_free()
     !
     if(n_steps>0) call live_timing()
     !
   endif
   !
   if(io_KB_pwscf_err==0) then 
     !
     pp_kb=0._SP
     pp_kbd=0._SP
     !
     if (wf_ncx_new/=wf_ncx_save) then
       !
       wf_ncx=wf_ncx_new
       !
       call PP_free()
       call PP_alloc_pwscf()
       !
       pp_kbs=pp_kbs_store
       !
       call io_control(ACTION=OP_WR_CL,COM=NONE,SEC=(/1/),MODE=DUMP,ID=ID)
       io_KB_pwscf_err=io_KB_pwscf(ID)
       !
       call live_timing('PPs comp. reduction.',k_save%nibz)
       !
       do ik=1,k_save%nibz
         !
         ik_save=kpoints_map(1,ik)
         !
         pp_kb(:,:,:,:) =pp_kb_store(:wf_ncx_new,:,:,:,ik_save)
         pp_kbd(:,:,:,:)=pp_kbd_store(:wf_ncx_new,:,:,:,ik_save)
         !
         call io_control(ACTION=OP_APP_WR_CL,SEC=(/ik+1/),ID=ID)
         io_KB_pwscf_err=io_KB_pwscf(ID)
         !
         call live_timing(steps=1)
         !
       enddo
       !
       call live_timing()
       !
     endif
     !
     if(n_steps>0) call live_timing('PPs rotation',n_steps)
     !
     do ik=k_save%nibz+1,k%nibz
       !
       ik_save=kpoints_map(1,ik)
       is=kpoints_map(2,ik)
       !
       do ic=1,wf_nc_k_reduced(ik_save)
         ig_rot=g_rot(is,wf_igk_reduced(ic,ik_save))
         do ic_rot=1,wf_nc_k_new(ik)
           ig=wf_igk_new(ic_rot,ik)
           if(ig==ig_rot) exit
         enddo
         !
         pp_kb(ic_rot,:,:,:) =pp_kb_store(ic,:,:,:,ik_save)
         pp_kbd(ic_rot,:,:,:)=pp_kbd_store(ic,:,:,:,ik_save)
         !
       enddo
       !
       call io_control(ACTION=OP_APP_WR_CL,COM=NONE,SEC=(/ik+1/),ID=ID)      
       io_KB_pwscf_err=io_KB_pwscf(ID)
       !
       call live_timing(steps=1)
       !
     enddo
     !
     deallocate(pp_kb_store,pp_kbd_store,pp_kbs_store)
     call mem_est("pp_kb_store pp_kbd_store")
     !
     call PP_free()
     !
     if(n_steps>0) call live_timing()
     !
   endif
   !
   if(io_Vnl_err==0) then 
     !
     allocate(Vnl(3,E%nb,E%nbm,k%nibz,n_sp_pol))
     !
     Vnl(1:3, 1:E%nb, 1:E%nbm, 1:k_save%nibz, 1:n_sp_pol)=&
  &       Vnl_store(1:3, 1:E%nb, 1:E%nbm, 1:k_save%nibz, 1:n_sp_pol)
     !
     if(n_steps>0) call live_timing('PPs rotation',n_steps)
     !
     do ik=k_save%nibz+1,k%nibz
       !
       ik_save=kpoints_map(1,ik)
       is=kpoints_map(2,ik)
       !
       forall(ib=1:E%nb,ibm=1:E%nbm,i_spin=1:n_sp_pol) &
  &          Vnl(:,ib,ibm,ik,i_spin) = matmul( old_dl_sop(:,:,is), Vnl_store(:,ib,ibm,ik_save,i_spin) ) 
       ! Vnl is invariant under T-rev as iR and p ??
       if ( S_contains_TR(is) ) Vnl(:,:,:,ik,:)=conjg( Vnl(:,:,:,ik,:) )
       !
       call live_timing(steps=1)
       !
     enddo
     !
     X_Vnl%ngostnts=wf_ng
     nXkibz=k%nibz
     call io_control(ACTION=OP_WR_CL,COM=NONE,SEC=(/1,2/),ID=ID)      
     io_Vnl_err=io_Vnl(X_Vnl,E,ID)
     !
     deallocate(Vnl,Vnl_store)
     call mem_est("Vnl Vnl_store")
     !
     if(n_steps>0) call live_timing()
     !
   endif
   !
 case(2)
   !
   if(io_KB_abinit_err==0.or.io_KB_pwscf_err==0.or.io_Vnl_err==0) call msg('s',':: PPs reduction...')
   !
   if(io_KB_abinit_err==0) then
     !
     call PP_free()
     call PP_alloc_abinit()
     pp_kb=0._SP
     pp_kbd=0._SP
     pp_kbs=pp_kbs_store
     !
     call io_control(ACTION=OP_WR_CL,COM=NONE,SEC=(/1/),MODE=DUMP,ID=ID)
     io_KB_abinit_err=io_KB_abinit(ID) 
     !
     do ik=1,k%nibz
       !
       pp_kb(:ng_closed,:,:,:) =pp_kb_store(:ng_closed,:,:,:,kpoints_map(1,ik))
       pp_kbd(:ng_closed,:,:,:)=pp_kbd_store(:ng_closed,:,:,:,kpoints_map(1,ik))     
       !
       call io_control(ACTION=OP_APP_WR_CL,COM=NONE,SEC=(/ik+1/),ID=ID)      
       io_KB_abinit_err=io_KB_abinit(ID)
       !
     enddo
     !
     deallocate(pp_kb_store,pp_kbd_store,pp_kbs_store)
     call mem_est("pp_kb_store pp_kbd_store")
     call PP_free()
     !
   endif
   !
   if(io_KB_pwscf_err==0) then
     !
     call PP_free()
     call PP_alloc_pwscf()
     pp_kb=0._SP
     pp_kbd=0._SP
     pp_kbs=pp_kbs_store
     !
     call io_control(ACTION=OP_WR_CL,COM=NONE,SEC=(/1/),MODE=DUMP,ID=ID)
     io_KB_pwscf_err=io_KB_pwscf(ID) 
     !
     do ik=1,k%nibz
       !
       pp_kb(:wf_ncx,:,:,:) =pp_kb_store(:wf_ncx,:,:,:,kpoints_map(1,ik))
       pp_kbd(:wf_ncx,:,:,:)=pp_kbd_store(:wf_ncx,:,:,:,kpoints_map(1,ik))     
       !
       call io_control(ACTION=OP_APP_WR_CL,COM=NONE,SEC=(/ik+1/),ID=ID)      
       io_KB_pwscf_err=io_KB_pwscf(ID)
       !
     enddo
     !
     deallocate(pp_kb_store,pp_kbd_store,pp_kbs_store)
     call mem_est("pp_kb_store pp_kbd_store")
     call PP_free()
     !
   endif
   !
   if(io_Vnl_err==0) then
     !
     allocate(Vnl(3,E%nb,E%nbm,k%nibz,n_sp_pol))
     !
     forall(ik=1:k%nibz) Vnl(:,:,:,ik,:) = Vnl_store(:,:,:,kpoints_map(1,ik),:)
     !
     X_Vnl%ngostnts=wf_ng
     nXkibz=k%nibz
     call io_control(ACTION=OP_WR_CL,COM=NONE,SEC=(/1,2/),ID=ID)
     io_Vnl_err=io_Vnl(X_Vnl,E,ID)
     !
     deallocate(Vnl_store,Vnl)
     call mem_est("Vnl_store Vnl") 
     !
   endif
   !
   call msg('l','done')
   !
 end select
 !
 deallocate(wf_nc_k_reduced,wf_igk_reduced)
 deallocate(wf_nc_k_save,   wf_igk_save   )
 deallocate(wf_nc_k_new,    wf_igk_new    )
 !
 core_io_path=core_io_path_save
 !
end subroutine
