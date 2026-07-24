select * from dba_tablespaces
where tablespace_name in ('DATA2024','INDX2024','DATA2025','INDX2025','DATA_LOG','INDX_LOG','FDA_TS','DATA3','APP_TS','BIG_TS');

select * from dba_tab_partitions where tablespace_name  in ('DATA2024','INDX2024','DATA2025','INDX2025','DATA_LOG','INDX_LOG','FDA_TS','DATA3','APP_TS','BIG_TS');

select * from dba_tables where tablespace_name  in ('DATA2024','INDX2024','DATA2025','INDX2025','DATA_LOG','','FDA_TS','DATA3','APP_TS','BIG_TS');

drop table SYS.DDL_LOG purge;

drop  trigger SYS.DDL_TRIG;

ALTER TRIGGER SYS.DDL_TRIG DISABLE;

drop table FDA_TEST_USER.SYS_FBA_TCRV_75319 purge;

drop table FDA_TEST_USER.SYS_FBA_DDL_COLMAP_75319 purge;

drop user oaz23 cascade;

--OAZ19	TABLE1
--FDA_TEST_USER	SYS_FBA_HIST_75319

select distinct table_owner, table_name from dba_tab_partitions where tablespace_name  in ('DATA2024','INDX2024','DATA2025','INDX2025','DATA_LOG','','FDA_TS');

--[Error] Execution (11: 18): ORA-04098: trigger 'SYS.DDL_TRIG' is invalid and failed re-validation


drop table OAZ19.TABLE1 purge;

drop table FDA_TEST_USER.SYS_FBA_HIST_75319 ;

drop user FDA_TEST_USER;

DATA	10	100	90	10	90	327680	0	ONLINE	PERMANENT
DATA2021	5	200	190	10	95	327680	0	ONLINE	PERMANENT
DATA2024	10	100	90	10	90	327680	0	ONLINE	PERMANENT
DATA_LOG	10	100	90	10	90	327680	0	ONLINE	PERMANENT
DATA_NGHIEPVU1	10	100	90	10	90	327680	0	ONLINE	PERMANENT
DATA_OMF	10	100	90	10	90	327680	0	ONLINE	PERMANENT
DUMP	10	100	90	10	90	327680	0	ONLINE	PERMANENT
FDA_TS	10	91	82	9	90	327680	0	ONLINE	PERMANENT
FDA_TS2	10	91	82	9	90	327680	0	ONLINE	PERMANENT
INDX	10	100	90	10	90	327680	0	ONLINE	PERMANENT
INDX2021	10	100	90	10	90	327680	0	ONLINE	PERMANENT
INDX2024	10	100	90	10	90	327680	0	ONLINE	PERMANENT
INDX_LOG	10	100	90	10	90	327680	0	ONLINE	PERMANENT
INDX_NGHIEPVU1	10	100	90	10	90	327680	0	ONLINE	PERMANENT
SYSAUX	78	450	99	351	22	327680	0	ONLINE	PERMANENT
SYSTEM	75	380	97	283	25	327680	0	ONLINE	PERMANENT
TEMP	0	36	36	0	100	32768	0	ONLINE	TEMPORARY
UNDOTBS1	25	190	142	48	75	327680	0	ONLINE	UNDO
USERS	11	95	84	11	89	327680	0	ONLINE	PERMANENT

APP	2	120	117	3	98	98304	0	ONLINE	PERMANENT
APP_INDX	2	120	117	3	98	98304	0	ONLINE	PERMANENT
APP_TS2	2	180	176	4	98	98454	0	ONLINE	PERMANENT
FDA_TS	11	21	19	2	89	98304	0	ONLINE	PERMANENT
LOB	10	21	19	2	90	98304	0	ONLINE	PERMANENT


drop tablespace DATA including contents and datafiles;
drop tablespace INDX including contents and datafiles;
drop tablespace DATA2021 including contents and datafiles;
drop tablespace INDX2021 including contents and datafiles;
drop tablespace DATA2024 including contents and datafiles;
drop tablespace INDX2024 including contents and datafiles;
drop tablespace DATA2025 including contents and datafiles;
drop tablespace INDX2025 including contents and datafiles;
drop tablespace DATA2026 including contents and datafiles;
drop tablespace INDX2026 including contents and datafiles;
drop tablespace DATA202504 including contents and datafiles;
drop tablespace DATA_NGHIEPVU1 including contents and datafiles;
drop tablespace INDX_NGHIEPVU1 including contents and datafiles;
drop tablespace DATA_LOG including contents and datafiles;
drop tablespace INDX_LOG including contents and datafiles;
drop tablespace DATA_AUDIT including contents and datafiles;
drop tablespace INDX_AUDIT including contents and datafiles;
drop tablespace DUMP including contents and datafiles;
drop tablespace LOB including contents and datafiles;
drop tablespace BIG_TS including contents and datafiles;

drop tablespace DATA3 including contents and datafiles;
drop tablespace APP_TS including contents and datafiles;



