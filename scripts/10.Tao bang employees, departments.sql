create user hr identified by oracle;

grant connect,resource, select any table, unlimited tablespace to hr;

-- create tables
create table hr.dept (
department_id number constraint department_fk primary key,
    name                           varchar2(255) not null,
    location                       varchar2(4000),
    country                        varchar2(4000)
)
;

create table hr.emp (
    department_id                  number                                  ,
    name                           varchar2(50) not null,
    email                          varchar2(255),
    cost_center                    number,
    date_hired                     date,
    job                            varchar2(255)
)
;


---- triggers
--create or replace trigger departments_biu
--    before insert or update 
--    on departments
--    for each row
--begin
--    null;
--end departments_biu;
--/
--
--create or replace trigger employees_biu
--    before insert or update 
--    on employees
--    for each row
--begin
--    :new.email := lower(:new.email);
--end employees_biu;
--/


-- indexes
create index hr.emp_i1 on hr.emp (department_id);

---- create views
--create or replace view emp_v as 
--select 
--    departments.name                                   department_name,
--    departments.location                               location,
--    departments.country                                country,
--    employees.name                                     employee_name,
--    employees.email                                    email,
--    employees.cost_center                              cost_center,
--    employees.date_hired                               date_hired,
--    employees.job                                      job
--from 
--    departments,
--    employees
--where
--    employees.department_id(+) = departments.id
--/

-- load data
 

insert into dept values (
1,
    'Customer Satisfaction',
    'Tanquecitos',
    'United States'
);

insert into dept values (2,
    'Facilities',
    'Sugarloaf',
    'United States'
);

insert into dept values (3,
    'Product Support',
    'Dale City',
    'United States'
);

insert into dept values (4,
    'Internal Systems',
    'Grosvenor',
    'United States'
);

commit;
commit;
-- load data
 
insert into emp (
    department_id,
    name,
    email,
    cost_center,
    date_hired,
    job
) values (
    1,
    'Gricelda Luebbers',
    'gricelda.luebbers@aaab.com',
    28,
    sysdate - 64,
    'Customer Advocate'
);

insert into emp (
    department_id,
    name,
    email,
    cost_center,
    date_hired,
    job
) values (
    1,
    'Dean Bollich',
    'dean.bollich@aaac.com',
    57,
    sysdate - 95,
    'President'
);

insert into emp (
    department_id,
    name,
    email,
    cost_center,
    date_hired,
    job
) values (
    1,
    'Milo Manoni',
    'milo.manoni@aaad.com',
    33,
    sysdate - 87,
    'Systems Designer'
);

insert into emp (
    department_id,
    name,
    email,
    cost_center,
    date_hired,
    job
) values (
    1,
    'Laurice Karl',
    'laurice.karl@aaae.com',
    63,
    sysdate - 80,
    'System Operations'
);

insert into emp (
    department_id,
    name,
    email,
    cost_center,
    date_hired,
    job
) values (
    1,
    'August Rupel',
    'august.rupel@aaaf.com',
    77,
    sysdate - 54,
    'Security Specialist'
);

insert into emp (
    department_id,
    name,
    email,
    cost_center,
    date_hired,
    job
) values (
    1,
    'Salome Guisti',
    'salome.guisti@aaag.com',
    77,
    sysdate - 88,
    'President'
);

insert into emp (
    department_id,
    name,
    email,
    cost_center,
    date_hired,
    job
) values (
    1,
    'Lovie Ritacco',
    'lovie.ritacco@aaah.com',
    74,
    sysdate - 56,
    'Solustions Specialist'
);

insert into emp (
    department_id,
    name,
    email,
    cost_center,
    date_hired,
    job
) values (
    1,
    'Chaya Greczkowski',
    'chaya.greczkowski@aaai.com',
    77,
    sysdate - 76,
    'Web Developer'
);

insert into emp (
    department_id,
    name,
    email,
    cost_center,
    date_hired,
    job
) values (
    1,
    'Twila Coolbeth',
    'twila.coolbeth@aaaj.com',
    87,
    sysdate - 66,
    'Business Applications'
);

insert into emp (
    department_id,
    name,
    email,
    cost_center,
    date_hired,
    job
) values (
    1,
    'Carlotta Achenbach',
    'carlotta.achenbach@aaak.com',
    49,
    sysdate - 91,
    'Webmaster'
);

insert into emp (
    department_id,
    name,
    email,
    cost_center,
    date_hired,
    job
) values (
    1,
    'Jeraldine Audet',
    'jeraldine.audet@aaal.com',
    57,
    sysdate - 27,
    'Programmer Analyst'
);

insert into emp (
    department_id,
    name,
    email,
    cost_center,
    date_hired,
    job
) values (
    1,
    'August Arouri',
    'august.arouri@aaam.com',
    5,
    sysdate - 62,
    'Executive Engineer'
);

insert into emp (
    department_id,
    name,
    email,
    cost_center,
    date_hired,
    job
) values (
    1,
    'Ward Stepney',
    'ward.stepney@aaan.com',
    24,
    sysdate - 13,
    'Accounting Analyst'
);

insert into emp (
    department_id,
    name,
    email,
    cost_center,
    date_hired,
    job
) values (
    1,
    'Ayana Barkhurst',
    'ayana.barkhurst@aaao.com',
    5,
    sysdate - 36,
    'Programmer Analyst'
);

commit;