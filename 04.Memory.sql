--CHECK
--SGA Stats	
select * from v$sga_dynamic_components;

--PGA usage statistics:
	select * from v$pgastat;
	
-- Determine a good setting for pga_aggregate_target:
	select * from v$pga_target_advice order by pga_target_for_estimate;

-- Show the maximum PGA usage per process:
select max(pga_used_mem), max(pga_alloc_mem), max(pga_max_mem) from v$process;
	 
select * from v$sga_target_advice order by sga_size;
	
select * from V$SGASTAT;

	
--1. THAY ĐỔI THAM SỐ
	
--· Kết nối đến instance ASM:
	$ . grid
	$ sqlplus / as sysdba
	
-- Thay đổi tham số memory_max_target trên các instance ASM:
	Trên instance ASM của node 1:
	SQL> alter system set memory_max_target =1040M scope=’spfile’ SID=’+ASM1’;
	Trên instance ASM của node 2:
	SQL> alter system set memory_max_target =1040M scope=’spfile’ SID=’+ASM2’;
	
-- Thay đổi tham số memory_target trên các instance ASM:
	Trên instance ASM của node 1:
	SQL> alter system set memory_target=1040M scope=’spfile’ SID=’+ASM1’;
	Trên instance ASM của node 2:
	SQL> alter system set memory_target=1040M scope=’spfile’ SID=’+ASM2’;
	
--· Thay đổi tham số sga_max_size trên các instance ASM:
	Trên instance ASM của node 1:
	SQL> alter system set sga_max_size =1040M scope=’spfile’ SID=’+ASM1’;
	Trên instance ASM của node 2:
	SQL> alter system set sga_max_size =1040M scope=’spfile’ SID=’+ASM2’;
	
--2.KHỞI ĐỘNG LẠI RAC
	
--· Shutdown instance database trên node 1:
	SQL> shutdown immediate
	
	+ Shutdown instance ASM trên node 1:
	
	SQL> connect / as sysasm
	
	SQL> shutdown immediate
	
--· Startup instance ASM trên node 1:
	SQL> startup
	
	+ Startup instance database trên node 1:
	SQL> startup
	
--· Kiểm tra tham số memory_target, memory_max_target sau khi instance database, ASM trên node 1 được bật lên 
	SQL> show parameter memory;
	
	$ crsctl status resource –t
	
· Sau khi các tham số memory_target, memory_max_target được thay đổi đúng thì thực hiện restart lại node 2 theo các bước tương tự trên.
	
--3. KIỂM TRA LẠI
	Kiểm tra CSDL theo khi thay đổi tham số
	
	Lưu ý: Do OCS, Voting lưu trong diskgroup do đó phải bật instance ASM thì CRS mới online được (CSS thì luôn online)
	
Một số lệnh bổ sung// start, stop all service clusterware
	root# /u01/grid/bin/crs_start -all
	root# /u01/grid/bin/crs_stop -all
	
	// Kiem tra CRS
	$ crs_stat -a
