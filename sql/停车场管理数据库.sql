-- =====================================================================
-- 停车场管理系统 数据库脚本（MySQL 8.0）
-- 课程：数据库原理与应用　项目：停车场管理数据库项目
-- 版本：1.0　　生成日期：2026-10-19
--
-- 运行环境：MySQL 8.0.16 及以上版本（CHECK 约束自 8.0.16 起被强制执行），
--           推荐 MySQL 8.0.30+，本脚本已在 MySQL 8.0.46 上验证通过。
-- 执行方式：MySQL Workbench 8.0 CE 整篇执行，或在 mysql 命令行执行
--           SOURCE 本文件。
--
-- 说明：
--   1. 本脚本可重复执行：重复执行会按外键依赖倒序删除并重建 8 张业务表，
--      重新装载样例数据；不会删除数据库本身，避免误删库内其他对象。
--   2. 表名、字段名与《../docs/01_需求与数据库模型.md》保持一致，源码标识符使用英文 snake_case。
--   3. “同一车辆只能有一条未出场记录”“同一车位只能有一条未出场记录”
--      “同一车辆生效合同日期不重叠”属于跨记录业务约束，单个 CHECK 无法实现，
--      需由应用层事务/触发器校验，脚本末附有说明。
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. 建库与环境设置
-- ---------------------------------------------------------------------
SET NAMES utf8mb4;

CREATE DATABASE IF NOT EXISTS `parking_management_db`
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_0900_ai_ci;

USE `parking_management_db`;

-- 为保证脚本可重复执行，先按依赖倒序删除旧表
SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS `payment_record`;
DROP TABLE IF EXISTS `parking_record`;
DROP TABLE IF EXISTS `rental_contract`;
DROP TABLE IF EXISTS `charge_rule`;
DROP TABLE IF EXISTS `vehicle`;
DROP TABLE IF EXISTS `parking_space`;
DROP TABLE IF EXISTS `vehicle_owner`;
DROP TABLE IF EXISTS `administrator`;
SET FOREIGN_KEY_CHECKS = 1;

-- ---------------------------------------------------------------------
-- 1. 建表（按外键依赖顺序创建）
-- ---------------------------------------------------------------------

-- 1.1 管理员表（Administrator）：记录办理业务的系统操作人员
CREATE TABLE `administrator` (
    `administrator_id`       BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '管理员内部标识（主键）',
    `employee_no`           VARCHAR(20)     NOT NULL                COMMENT '员工业务编号（唯一）',
    `name`           VARCHAR(50)     NOT NULL                COMMENT '管理员姓名',
    `phone`       VARCHAR(20)     NOT NULL                COMMENT '联系方式（唯一）',
    `login_account`       VARCHAR(30)     NOT NULL                COMMENT '系统登录账号（唯一）',
    `role`           VARCHAR(20)     NOT NULL                COMMENT '收费员/主管/系统管理员',
    `account_status`       VARCHAR(10)     NOT NULL DEFAULT '启用' COMMENT '启用/停用',
    `created_at`       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '账号创建时间',
    PRIMARY KEY (`administrator_id`),
    UNIQUE KEY `uk_administrator_employee_no` (`employee_no`),
    UNIQUE KEY `uk_administrator_phone` (`phone`),
    UNIQUE KEY `uk_administrator_login_account` (`login_account`),
    CONSTRAINT `chk_administrator_role` CHECK (`role` IN ('收费员', '主管', '系统管理员')),
    CONSTRAINT `chk_administrator_account_status` CHECK (`account_status` IN ('启用', '停用'))
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci
  COMMENT = '管理员表：保存操作人员信息，并关联其办理的业务记录';

-- 1.2 车主表（Owner）：保存车主基本资料及联系方式
CREATE TABLE `vehicle_owner` (
    `owner_id`       BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '车主内部标识（主键）',
    `name`         VARCHAR(50)     NOT NULL                COMMENT '车主姓名',
    `id_number`     CHAR(18)        NOT NULL                COMMENT '实名识别（唯一）',
    `phone`     VARCHAR(20)     NOT NULL                COMMENT '联系方式（唯一）',
    `address`     VARCHAR(200)    NULL                    COMMENT '可选地址',
    `owner_status`     VARCHAR(10)     NOT NULL DEFAULT '正常' COMMENT '正常/停用',
    `created_at`     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '登记时间',
    PRIMARY KEY (`owner_id`),
    UNIQUE KEY `uk_owner_id_number` (`id_number`),
    UNIQUE KEY `uk_owner_phone` (`phone`),
    CONSTRAINT `chk_owner_status` CHECK (`owner_status` IN ('正常', '停用'))
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci
  COMMENT = '车主表：保存车主基本资料及联系方式';

-- 1.3 车位表（ParkingSpace）：保存车位编号、区域和使用状态
CREATE TABLE `parking_space` (
    `parking_space_id`       BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '车位内部标识（主键）',
    `space_code`     VARCHAR(20)     NOT NULL                COMMENT '现场标识（唯一）',
    `area`         VARCHAR(30)     NOT NULL                COMMENT '车位所属区域',
    `space_type`     VARCHAR(20)     NOT NULL                COMMENT '标准/无障碍/充电',
    `space_status`     VARCHAR(10)     NOT NULL DEFAULT '可用' COMMENT '可用/占用/停用',
    `location_note`     VARCHAR(100)    NULL                    COMMENT '车位位置补充说明',
    PRIMARY KEY (`parking_space_id`),
    UNIQUE KEY `uk_parking_space_code` (`space_code`),
    CONSTRAINT `chk_parking_space_type` CHECK (`space_type` IN ('标准', '无障碍', '充电')),
    CONSTRAINT `chk_parking_space_status` CHECK (`space_status` IN ('可用', '占用', '停用'))
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci
  COMMENT = '车位表：保存车位编号、区域和使用状态';

-- 1.4 车辆表（Vehicle）：保存车牌、车型等车辆信息，并关联车主
CREATE TABLE `vehicle` (
    `vehicle_id`       BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '车辆内部标识（主键）',
    `license_plate`       VARCHAR(12)     NOT NULL                COMMENT '车辆唯一识别（唯一）',
    `vehicle_type`     VARCHAR(20)     NOT NULL                COMMENT '小型车/大型车/新能源',
    `vehicle_color`     VARCHAR(20)     NULL                    COMMENT '外观颜色',
    `owner_id`       BIGINT UNSIGNED NOT NULL                COMMENT '外键：参照 车主(车主ID)',
    `vehicle_status`     VARCHAR(10)     NOT NULL DEFAULT '正常' COMMENT '正常/停用',
    `registered_at`     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '登记时间',
    PRIMARY KEY (`vehicle_id`),
    UNIQUE KEY `uk_vehicle_license_plate` (`license_plate`),
    KEY `idx_vehicle_owner_id` (`owner_id`),
    CONSTRAINT `fk_vehicle_owner_id` FOREIGN KEY (`owner_id`)
        REFERENCES `vehicle_owner` (`owner_id`) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT `chk_vehicle_type` CHECK (`vehicle_type` IN ('小型车', '大型车', '新能源')),
    CONSTRAINT `chk_vehicle_status` CHECK (`vehicle_status` IN ('正常', '停用'))
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci
  COMMENT = '车辆表：保存车牌、车型等车辆信息，并关联车主';

-- 1.5 收费规则表（ChargeRule）：保存临时停车计费参数
CREATE TABLE `charge_rule` (
    `charge_rule_id`       BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '规则标识（主键）',
    `rule_name`         VARCHAR(50)     NOT NULL                COMMENT '规则名称（唯一）',
    `hourly_rate`       DECIMAL(10,2)   NOT NULL                COMMENT '临停小时单价（大于 0）',
    `minimum_charge`         DECIMAL(10,2)   NOT NULL DEFAULT 0.00   COMMENT '最低应收金额（大于等于 0）',
    `daily_cap`     DECIMAL(10,2)   NULL                    COMMENT '可选每日封顶（大于 0）',
    `effective_date`         DATE            NOT NULL                COMMENT '规则开始日期',
    `expiry_date`         DATE            NULL                    COMMENT '为空表示仍有效',
    `rule_status`         VARCHAR(10)     NOT NULL DEFAULT '启用' COMMENT '启用/停用',
    `created_by_administrator_id`     BIGINT UNSIGNED NOT NULL                COMMENT '外键：参照 管理员(管理员ID)',
    PRIMARY KEY (`charge_rule_id`),
    UNIQUE KEY `uk_charge_rule_name` (`rule_name`),
    KEY `idx_charge_rule_created_by_administrator_id` (`created_by_administrator_id`),
    CONSTRAINT `fk_charge_rule_created_by_administrator_id` FOREIGN KEY (`created_by_administrator_id`)
        REFERENCES `administrator` (`administrator_id`) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT `chk_charge_rule_hourly_rate` CHECK (`hourly_rate` > 0),
    CONSTRAINT `chk_charge_rule_minimum_charge` CHECK (`minimum_charge` >= 0),
    CONSTRAINT `chk_charge_rule_daily_cap` CHECK (`daily_cap` IS NULL OR `daily_cap` > 0),
    CONSTRAINT `chk_charge_rule_expiry_date` CHECK (`expiry_date` IS NULL OR `expiry_date` >= `effective_date`),
    CONSTRAINT `chk_charge_rule_status` CHECK (`rule_status` IN ('启用', '停用'))
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci
  COMMENT = '收费规则表：保存临时停车计费参数及生效期限';

-- 1.6 月租合同表（MonthlyContract）：保存车辆月租期限、状态和收费信息
CREATE TABLE `rental_contract` (
    `rental_contract_id`      BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '合同标识（主键）',
    `contract_no`        VARCHAR(30)     NOT NULL                COMMENT '合同业务编号（唯一）',
    `vehicle_id`          BIGINT UNSIGNED NOT NULL                COMMENT '外键：参照 车辆(车辆ID)',
    `start_date`        DATE            NOT NULL                COMMENT '合同开始日',
    `end_date`        DATE            NOT NULL                COMMENT '合同结束日（不早于开始日期）',
    `monthly_rent`        DECIMAL(10,2)   NOT NULL                COMMENT '每月应缴金额（大于 0）',
    `deposit`            DECIMAL(10,2)   NOT NULL DEFAULT 0.00   COMMENT '可选押金（大于等于 0）',
    `contract_status`        VARCHAR(10)     NOT NULL DEFAULT '生效' COMMENT '生效/到期/终止',
    `signed_at`        DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '业务时间',
    `handled_by_administrator_id`    BIGINT UNSIGNED NOT NULL                COMMENT '外键：参照 管理员(管理员ID)',
    `remark`            VARCHAR(200)    NULL                    COMMENT '合同说明',
    PRIMARY KEY (`rental_contract_id`),
    UNIQUE KEY `uk_rental_contract_no` (`contract_no`),
    KEY `idx_rental_contract_vehicle_id` (`vehicle_id`),
    KEY `idx_rental_contract_vehicle_dates` (`vehicle_id`, `start_date`, `end_date`),
    CONSTRAINT `fk_rental_contract_vehicle_id` FOREIGN KEY (`vehicle_id`)
        REFERENCES `vehicle` (`vehicle_id`) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT `fk_rental_contract_handled_by_administrator_id` FOREIGN KEY (`handled_by_administrator_id`)
        REFERENCES `administrator` (`administrator_id`) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT `chk_rental_contract_start_end_date` CHECK (`start_date` <= `end_date`),
    CONSTRAINT `chk_rental_contract_monthly_rent` CHECK (`monthly_rent` > 0),
    CONSTRAINT `chk_rental_contract_deposit` CHECK (`deposit` >= 0),
    CONSTRAINT `chk_rental_contract_status` CHECK (`contract_status` IN ('生效', '到期', '终止'))
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci
  COMMENT = '月租合同表：保存车辆月租期限、状态和收费信息';

-- 1.7 停车记录表（ParkingRecord）：记录车辆入场、出场、占用车位、时长和应收费用
CREATE TABLE `parking_record` (
    `parking_record_id`      BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '一次进出场标识（主键）',
    `vehicle_id`          BIGINT UNSIGNED NOT NULL                COMMENT '外键：参照 车辆(车辆ID)',
    `parking_space_id`          BIGINT UNSIGNED NOT NULL                COMMENT '外键：参照 车位(车位ID)',
    `parking_type`        VARCHAR(10)     NOT NULL                COMMENT '临时停车/月租停车',
    `charge_rule_id`      BIGINT UNSIGNED NULL                    COMMENT '临停时关联收费规则，月租为空',
    `rental_contract_id`      BIGINT UNSIGNED NULL                    COMMENT '月租时关联有效合同，临停为空',
    `entry_time`        DATETIME        NOT NULL                COMMENT '车辆入场时间',
    `exit_time`        DATETIME        NULL                    COMMENT '未出场为空，且不早于入场时间',
    `duration_minutes`    INT UNSIGNED    NULL                    COMMENT '出场时计算，非负',
    `amount_due`        DECIMAL(10,2)   NOT NULL DEFAULT 0.00   COMMENT '临停计算金额，月租为 0',
    `record_status`        VARCHAR(10)     NOT NULL DEFAULT '在场' COMMENT '在场/已出场/异常',
    `handled_by_administrator_id`    BIGINT UNSIGNED NOT NULL                COMMENT '外键：参照 管理员(管理员ID)',
    `remark`            VARCHAR(200)    NULL                    COMMENT '异常或人工说明',
    PRIMARY KEY (`parking_record_id`),
    KEY `idx_record_vehicle_entry` (`vehicle_id`, `entry_time`),
    KEY `idx_record_space_entry` (`parking_space_id`, `entry_time`),
    KEY `idx_record_status` (`record_status`),
    CONSTRAINT `fk_record_vehicle_id` FOREIGN KEY (`vehicle_id`)
        REFERENCES `vehicle` (`vehicle_id`) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT `fk_record_parking_space_id` FOREIGN KEY (`parking_space_id`)
        REFERENCES `parking_space` (`parking_space_id`) ON UPDATE CASCADE ON DELETE RESTRICT,
    -- MySQL 8.0 限制：参与 CHECK 互斥约束的列不能带 CASCADE 更新动作，故这两个外键用 RESTRICT
    CONSTRAINT `fk_record_charge_rule_id` FOREIGN KEY (`charge_rule_id`)
        REFERENCES `charge_rule` (`charge_rule_id`) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT `fk_record_rental_contract_id` FOREIGN KEY (`rental_contract_id`)
        REFERENCES `rental_contract` (`rental_contract_id`) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT `fk_record_handled_by_administrator_id` FOREIGN KEY (`handled_by_administrator_id`)
        REFERENCES `administrator` (`administrator_id`) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT `chk_record_parking_type` CHECK (`parking_type` IN ('临时停车', '月租停车')),
    CONSTRAINT `chk_record_rule_contract_exclusive` CHECK (
        (`parking_type` = '临时停车' AND `charge_rule_id` IS NOT NULL AND `rental_contract_id` IS NULL)
     OR (`parking_type` = '月租停车' AND `charge_rule_id` IS NULL AND `rental_contract_id` IS NOT NULL)
    ),
    CONSTRAINT `chk_record_entry_exit_time` CHECK (`exit_time` IS NULL OR `exit_time` >= `entry_time`),
    CONSTRAINT `chk_record_duration` CHECK (`duration_minutes` IS NULL OR `duration_minutes` >= 0),
    CONSTRAINT `chk_record_amount_due` CHECK (`amount_due` >= 0),
    CONSTRAINT `chk_record_status` CHECK (`record_status` IN ('在场', '已出场', '异常')),
    -- 在场/已出场的时间与时长组合由数据库强制；异常状态的组合语义暂未定义
    CONSTRAINT `chk_record_status_exit_consistency` CHECK (
        (`record_status` = '在场' AND `exit_time` IS NULL AND `duration_minutes` IS NULL)
     OR (`record_status` = '已出场' AND `exit_time` IS NOT NULL AND `duration_minutes` IS NOT NULL)
     OR (`record_status` = '异常')
    )
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci
  COMMENT = '停车记录表：记录车辆入场、出场、占用车位、时长和应收费用';

-- 1.8 缴费记录表（PaymentRecord）：记录停车费用或月租费用的支付信息
CREATE TABLE `payment_record` (
    `payment_record_id`      BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '缴费标识（主键）',
    `payment_no`      VARCHAR(40)     NOT NULL                COMMENT '外部/内部流水号（唯一）',
    `payment_type`        VARCHAR(10)     NOT NULL                COMMENT '临停停车费/月租费',
    `parking_record_id`      BIGINT UNSIGNED NULL                    COMMENT '临停缴费归属（与月租合同二选一）',
    `rental_contract_id`      BIGINT UNSIGNED NULL                    COMMENT '月租缴费归属（与停车记录二选一）',
    `amount_due`        DECIMAL(10,2)   NOT NULL                COMMENT '业务应收金额（大于等于 0）',
    `amount_paid`        DECIMAL(10,2)   NOT NULL                COMMENT '实际收款金额；待支付为 0',
    `payment_method`        VARCHAR(10)     NOT NULL                COMMENT '现金/微信/支付宝/银行卡',
    `payment_status`        VARCHAR(10)     NOT NULL DEFAULT '已支付' COMMENT '待支付/已支付/已退款',
    `paid_at`        DATETIME        NULL DEFAULT NULL        COMMENT '实际支付时间；待支付为空',
    `handled_by_administrator_id`    BIGINT UNSIGNED NOT NULL                COMMENT '外键：参照 管理员(管理员ID)',
    `remark`            VARCHAR(200)    NULL                    COMMENT '退款或人工说明',
    PRIMARY KEY (`payment_record_id`),
    UNIQUE KEY `uk_payment_no` (`payment_no`),
    KEY `idx_payment_paid_at` (`paid_at`, `payment_type`, `payment_status`),
    KEY `idx_payment_parking_record_id` (`parking_record_id`),
    KEY `idx_payment_rental_contract_id` (`rental_contract_id`),
    -- MySQL 8.0 限制：参与 CHECK 互斥约束的列不能带 CASCADE 更新动作，故这两个外键用 RESTRICT
    CONSTRAINT `fk_payment_parking_record_id` FOREIGN KEY (`parking_record_id`)
        REFERENCES `parking_record` (`parking_record_id`) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT `fk_payment_rental_contract_id` FOREIGN KEY (`rental_contract_id`)
        REFERENCES `rental_contract` (`rental_contract_id`) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT `fk_payment_handled_by_administrator_id` FOREIGN KEY (`handled_by_administrator_id`)
        REFERENCES `administrator` (`administrator_id`) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT `chk_payment_type` CHECK (`payment_type` IN ('临停停车费', '月租费')),
    CONSTRAINT `chk_payment_owner_exclusive` CHECK (
        (`parking_record_id` IS NOT NULL AND `rental_contract_id` IS NULL)
     OR (`parking_record_id` IS NULL AND `rental_contract_id` IS NOT NULL)
    ),
    CONSTRAINT `chk_payment_type_owner_consistency` CHECK (
        (`payment_type` = '临停停车费' AND `parking_record_id` IS NOT NULL)
     OR (`payment_type` = '月租费' AND `rental_contract_id` IS NOT NULL)
    ),
    CONSTRAINT `chk_payment_amount_due` CHECK (`amount_due` >= 0),
    CONSTRAINT `chk_payment_amount_paid` CHECK (`amount_paid` >= 0),
    CONSTRAINT `chk_payment_method` CHECK (`payment_method` IN ('现金', '微信', '支付宝', '银行卡')),
    CONSTRAINT `chk_payment_status` CHECK (`payment_status` IN ('待支付', '已支付', '已退款')),
    CONSTRAINT `chk_payment_status_amount_consistency` CHECK (
        (`payment_status` = '待支付' AND `amount_paid` = 0 AND `paid_at` IS NULL)
     OR (`payment_status` IN ('已支付', '已退款') AND `amount_paid` > 0 AND `paid_at` IS NOT NULL)
    )
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci
  COMMENT = '缴费记录表：记录停车费用或月租费用的支付信息';

-- ---------------------------------------------------------------------
-- 2. 样例数据（覆盖在场/已出场、临停/月租、已支付/已退款等场景）
-- ---------------------------------------------------------------------

-- 2.1 管理员：主管 1 名、收费员 2 名
INSERT INTO `administrator` (`administrator_id`, `employee_no`, `name`, `phone`, `login_account`, `role`, `account_status`, `created_at`) VALUES
(1, '1001', '张伟', '13800000001', 'zhangwei',   '主管',       '启用', '2026-01-01 09:00:00'),
(2, '1002', '李娜', '13800000002', 'lina',       '收费员',     '启用', '2026-01-01 09:10:00'),
(3, '1003', '王强', '13800000003', 'wangqiang',  '收费员',     '启用', '2026-02-15 14:00:00');

-- 2.2 车主：含 1 名已停用车主
INSERT INTO `vehicle_owner` (`owner_id`, `name`, `id_number`, `phone`, `address`, `owner_status`, `created_at`) VALUES
(1, '张三', '110101199001011234', '13911110001', '北京市朝阳区望京街道 1 号',   '正常', '2026-01-05 10:00:00'),
(2, '李四', '110101199202022345', '13911110002', '北京市海淀区中关村大街 2 号', '正常', '2026-01-06 11:00:00'),
(3, '王五', '110101198803033456', '13911110003', '北京市西城区复兴门外大街 3 号', '正常', '2026-02-10 15:30:00'),
(4, '赵六', '110101199504044567', '13911110004', '北京市丰台区南三环中路 4 号', '正常', '2026-03-01 09:00:00'),
(5, '陈七', '110101198606055678', '13911110005', '北京市通州区新华大街 5 号',  '停用', '2026-04-20 16:00:00');

-- 2.3 车位：A 区 6 个、B 区 4 个，A001/B001/B002 有在场车辆占用，A006 停用
INSERT INTO `parking_space` (`parking_space_id`, `space_code`, `area`, `space_type`, `space_status`, `location_note`) VALUES
(1,  'A001', 'A 区', '标准',   '占用', '电梯口旁'),
(2,  'A002', 'A 区', '标准',   '可用', NULL),
(3,  'A003', 'A 区', '充电',   '可用', '带充电桩'),
(4,  'A004', 'A 区', '标准',   '可用', NULL),
(5,  'A005', 'A 区', '无障碍', '可用', '无障碍专用'),
(6,  'A006', 'A 区', '标准',   '停用', '维修中'),
(7,  'B001', 'B 区', '标准',   '占用', '入口附近'),
(8,  'B002', 'B 区', '标准',   '占用', NULL),
(9,  'B003', 'B 区', '充电',   '可用', '带充电桩'),
(10, 'B004', 'B 区', '标准',   '可用', NULL);

-- 2.4 车辆：张三 2 辆、李四 2 辆、王五 1 辆、赵六 1 辆
INSERT INTO `vehicle` (`vehicle_id`, `license_plate`, `vehicle_type`, `vehicle_color`, `owner_id`, `vehicle_status`, `registered_at`) VALUES
(1, '京A12345', '小型车', '白色', 1, '正常', '2026-01-05 10:05:00'),
(2, '京B23456', '新能源', '蓝色', 1, '正常', '2026-01-05 10:06:00'),
(3, '京C34567', '小型车', '黑色', 2, '正常', '2026-01-06 11:05:00'),
(4, '京D45678', '大型车', '银色', 3, '正常', '2026-02-10 15:35:00'),
(5, '京E56789', '小型车', '红色', 4, '正常', '2026-03-01 09:05:00'),
(6, '京F67890', '小型车', '灰色', 2, '正常', '2026-03-05 10:00:00');

-- 2.5 收费规则：白天启用、夜间启用、节假日已失效停用
INSERT INTO `charge_rule` (`charge_rule_id`, `rule_name`, `hourly_rate`, `minimum_charge`, `daily_cap`, `effective_date`, `expiry_date`, `rule_status`, `created_by_administrator_id`) VALUES
(1, '白天临停收费规则', 5.00, 5.00, 50.00, '2026-01-01', NULL,         '启用', 1),
(2, '夜间临停收费规则', 3.00, 3.00, 30.00, '2026-01-01', NULL,         '启用', 1),
(3, '节假日收费规则',   8.00, 8.00, 80.00, '2026-05-01', '2026-09-30', '停用', 1);

-- 2.6 月租合同：2 份生效（其中 1 份将在 30 天内到期）、2 份已到期
INSERT INTO `rental_contract` (`rental_contract_id`, `contract_no`, `vehicle_id`, `start_date`, `end_date`, `monthly_rent`, `deposit`, `contract_status`, `signed_at`, `handled_by_administrator_id`, `remark`) VALUES
(1, 'HT-2026-001', 2, '2026-01-01', '2026-12-31', 500.00, 1000.00, '生效', '2025-12-20 10:00:00', 1, '张三月租年卡'),
(2, 'HT-2026-002', 3, '2026-09-01', '2026-11-10', 450.00, 1000.00, '生效', '2026-08-25 14:30:00', 2, NULL),
(3, 'HT-2026-003', 4, '2026-04-01', '2026-09-30', 600.00, 1000.00, '到期', '2026-03-20 09:00:00', 2, NULL),
(4, 'HT-2026-004', 3, '2026-01-01', '2026-08-31', 450.00, 1000.00, '到期', '2025-12-22 10:00:00', 1, NULL);

-- 2.7 停车记录：3 条在场（1 临停、2 月租），7 条已出场
-- 计费说明（按规则）：不足一小时按一小时计；
--   白天规则 5 元/小时、封顶 50 元；夜间规则 3 元/小时、封顶 30 元。
INSERT INTO `parking_record`
    (`parking_record_id`, `vehicle_id`, `parking_space_id`, `parking_type`, `charge_rule_id`, `rental_contract_id`,
     `entry_time`, `exit_time`, `duration_minutes`, `amount_due`, `record_status`, `handled_by_administrator_id`, `remark`) VALUES
(1, 6, 2, '临时停车', 1,    NULL, '2026-10-19 08:30:00', '2026-10-19 10:45:00', 135, 15.00, '已出场', 2, NULL),
(2, 5, 3, '临时停车', 1,    NULL, '2026-10-19 09:10:00', '2026-10-19 11:10:00', 120, 10.00, '已出场', 2, NULL),
(3, 1, 2, '临时停车', 1,    NULL, '2026-10-18 14:00:00', '2026-10-18 14:50:00',  50,  5.00, '已出场', 3, NULL),
(4, 1, 1, '临时停车', 1,    NULL, '2026-10-19 08:00:00', NULL,                    NULL, 0.00, '在场',   2, NULL),
(5, 2, 7, '月租停车', NULL, 1,    '2026-10-19 07:40:00', NULL,                    NULL, 0.00, '在场',   3, NULL),
(6, 3, 8, '月租停车', NULL, 2,    '2026-10-19 08:20:00', NULL,                    NULL, 0.00, '在场',   2, NULL),
(7, 4, 4, '临时停车', 2,    NULL, '2026-10-18 20:00:00', '2026-10-19 08:30:00', 750, 30.00, '已出场', 3, '跨夜封顶'),
(8, 1, 5, '临时停车', 1,    NULL, '2026-10-17 10:00:00', '2026-10-17 12:30:00', 150, 15.00, '已出场', 2, NULL),
(9, 2, 7, '月租停车', NULL, 1,    '2026-10-10 08:00:00', '2026-10-10 18:00:00', 600,  0.00, '已出场', 2, NULL),
(10, 3, 8, '月租停车', NULL, 2,    '2026-10-18 09:00:00', '2026-10-18 10:00:00',  60,  0.00, '已出场', 3, NULL);

-- 2.8 缴费记录：5 笔临停缴费、3 笔月租已支付、1 笔月租已退款
INSERT INTO `payment_record`
    (`payment_record_id`, `payment_no`, `payment_type`, `parking_record_id`, `rental_contract_id`,
     `amount_due`, `amount_paid`, `payment_method`, `payment_status`, `paid_at`, `handled_by_administrator_id`, `remark`) VALUES
(1, 'PAY-20261019-001', '临停停车费', 1,    NULL, 15.00, 15.00, '微信',   '已支付', '2026-10-19 10:46:00', 2, NULL),
(2, 'PAY-20261019-002', '临停停车费', 2,    NULL, 10.00, 10.00, '现金',   '已支付', '2026-10-19 11:12:00', 2, NULL),
(3, 'PAY-20261018-003', '临停停车费', 3,    NULL,  5.00,  5.00, '支付宝', '已支付', '2026-10-18 14:52:00', 3, NULL),
(4, 'PAY-20261019-004', '临停停车费', 7,    NULL, 30.00, 30.00, '银行卡', '已支付', '2026-10-19 08:35:00', 3, NULL),
(5, 'PAY-20261017-005', '临停停车费', 8,    NULL, 15.00, 15.00, '微信',   '已支付', '2026-10-17 12:31:00', 2, NULL),
(6, 'PAY-20261005-006', '月租费',     NULL,  1,    500.00, 500.00, '银行卡', '已支付', '2026-10-05 10:00:00', 1, 'HT-2026-001 十月月租'),
(7, 'PAY-20260901-007', '月租费',     NULL,  1,    500.00, 500.00, '银行卡', '已支付', '2026-09-01 09:00:00', 1, 'HT-2026-001 九月月租'),
(8, 'PAY-20261019-008', '月租费',     NULL,  2,    450.00, 450.00, '支付宝', '已支付', '2026-10-19 09:30:00', 2, 'HT-2026-002 十月月租'),
(9, 'PAY-20260901-009', '月租费',     NULL,  3,    600.00, 600.00, '微信',   '已退款', '2026-09-01 10:00:00', 2, '车辆转让，整月退款');

-- =====================================================================
-- 3. 查询
-- =====================================================================

-- ---------------------------------------------------------------------
-- 3.1 单表查询（3 个）
-- ---------------------------------------------------------------------

-- 【单表查询 1】当前在场的临时车辆
-- 用途：筛选尚未出场且属于临时停车的记录，支持管理员现场放行核对。
SELECT `parking_record_id`, `vehicle_id`, `parking_space_id`, `entry_time`, `record_status`
FROM `parking_record`
WHERE `parking_type` = '临时停车'
  AND `record_status` = '在场'
  AND `exit_time` IS NULL
ORDER BY `entry_time`;

-- 【单表查询 2】未来 30 天内到期的有效月租合同
-- 用途：生成月租续费提醒，不需要连接其他表即可得到合同清单。
SELECT `rental_contract_id`, `contract_no`, `vehicle_id`, `start_date`, `end_date`, `monthly_rent`
FROM `rental_contract`
WHERE `contract_status` = '生效'
  AND `end_date` BETWEEN CURRENT_DATE() AND DATE_ADD(CURRENT_DATE(), INTERVAL 30 DAY)
ORDER BY `end_date`;

-- 【单表查询 3】指定日期已支付的缴费流水（示例：2026-10-19）
-- 用途：按支付日期筛选已支付记录，核对当日收款流水。
SELECT `payment_no`, `payment_type`, `amount_due`, `amount_paid`, `payment_method`, `paid_at`
FROM `payment_record`
WHERE `payment_status` = '已支付'
  AND `paid_at` >= '2026-10-19 00:00:00'
  AND `paid_at` <  '2026-10-20 00:00:00'
ORDER BY `paid_at`;

-- ---------------------------------------------------------------------
-- 3.2 多表查询（3 个）
-- ---------------------------------------------------------------------

-- 【多表查询 1】在场车辆、车主和车位
-- 用途：管理员查看实时占用情况，体现停车记录、车辆、车主、车位四张表的连接。
SELECT v.`license_plate`, o.`name` AS `owner_name`,
       ps.`space_code`, ps.`area`, pr.`entry_time`, pr.`parking_type`
FROM `parking_record` pr
JOIN `vehicle` v  ON v.`vehicle_id` = pr.`vehicle_id`
JOIN `vehicle_owner` o  ON o.`owner_id` = v.`owner_id`
JOIN `parking_space` ps ON ps.`parking_space_id` = pr.`parking_space_id`
WHERE pr.`record_status` = '在场'
  AND pr.`exit_time` IS NULL
ORDER BY ps.`area`, ps.`space_code`;

-- 【多表查询 2】按月租合同统计已支付金额
-- 用途：查看每份合同的已收月租金额和缴费次数，包含尚未缴费的有效合同（左连接）。
SELECT mc.`contract_no`, v.`license_plate`, o.`name` AS `owner_name`,
       mc.`monthly_rent`,
       COALESCE(SUM(CASE WHEN p.`payment_status` = '已支付' THEN p.`amount_paid` ELSE 0 END), 0) AS `paid_amount`,
       COUNT(CASE WHEN p.`payment_status` = '已支付' THEN p.`payment_record_id` END) AS `paid_count`
FROM `rental_contract` mc
JOIN `vehicle` v ON v.`vehicle_id` = mc.`vehicle_id`
JOIN `vehicle_owner` o ON o.`owner_id` = v.`owner_id`
LEFT JOIN `payment_record` p ON p.`rental_contract_id` = mc.`rental_contract_id`
GROUP BY mc.`rental_contract_id`, mc.`contract_no`, v.`license_plate`, o.`name`, mc.`monthly_rent`
ORDER BY mc.`end_date`;

-- 【多表查询 3】按日期和缴费类型统计停车场收入
-- 用途：将已支付的临停和月租收入按日期、类型汇总并显示办理管理员。
SELECT DATE(p.`paid_at`) AS `payment_date`,
       p.`payment_type`, a.`name` AS `administrator_name`,
       COUNT(*) AS `payment_count`, SUM(p.`amount_paid`) AS `revenue_amount`
FROM `payment_record` p
JOIN `administrator` a ON a.`administrator_id` = p.`handled_by_administrator_id`
WHERE p.`payment_status` = '已支付'
GROUP BY DATE(p.`paid_at`), p.`payment_type`, a.`administrator_id`, a.`name`
ORDER BY `payment_date` DESC, p.`payment_type`, a.`administrator_id`;

-- ---------------------------------------------------------------------
-- 3.3 统计查询（必要的统计）
-- ---------------------------------------------------------------------

-- 【统计查询 1】按区域统计车位数量与占用情况
-- 用途：掌握各区域车位总量、占用、可用、停用及占用率，辅助现场调度。
SELECT ps.`area`,
       COUNT(*) AS `total_spaces`,
       SUM(ps.`space_status` = '占用') AS `occupied_spaces`,
       SUM(ps.`space_status` = '可用') AS `available_spaces`,
       SUM(ps.`space_status` = '停用') AS `disabled_spaces`,
       ROUND(SUM(ps.`space_status` = '占用') * 100.0 / COUNT(*), 2) AS `occupancy_rate`
FROM `parking_space` ps
GROUP BY ps.`area`
ORDER BY ps.`area`;

-- 【统计查询 2】车辆停车次数、累计时长与累计应收金额
-- 用途：生成车辆停车历史汇总，月租在场记录时长为空、不计入累计时长。
SELECT v.`license_plate`, o.`name` AS `owner_name`,
       COUNT(pr.`parking_record_id`) AS `parking_count`,
       COALESCE(SUM(pr.`duration_minutes`), 0) AS `total_duration_minutes`,
       COALESCE(SUM(pr.`amount_due`), 0) AS `total_amount_due`
FROM `vehicle` v
JOIN `vehicle_owner` o ON o.`owner_id` = v.`owner_id`
LEFT JOIN `parking_record` pr ON pr.`vehicle_id` = v.`vehicle_id`
GROUP BY v.`vehicle_id`, v.`license_plate`, o.`name`
ORDER BY `parking_count` DESC, v.`license_plate`;

-- 【统计查询 3】已支付收入总览（按缴费类型汇总并给出总计）
-- 用途：按临停停车费与月租费分类统计已支付收入，末行给出总计。
SELECT COALESCE(p.`payment_type`, '全部类型') AS `payment_type`,
       COUNT(*) AS `payment_count`,
       SUM(p.`amount_paid`) AS `total_amount_paid`
FROM `payment_record` p
WHERE p.`payment_status` = '已支付'
GROUP BY p.`payment_type` WITH ROLLUP;

-- 【统计查询 4】管理员业务办理量统计
-- 用途：统计各管理员办理的停车记录、月租合同与已支付缴费的笔数和金额。
SELECT a.`employee_no`, a.`name`, a.`role`,
       (SELECT COUNT(*) FROM `parking_record` pr WHERE pr.`handled_by_administrator_id` = a.`administrator_id`) AS `parking_record_count`,
       (SELECT COUNT(*) FROM `rental_contract` mc WHERE mc.`handled_by_administrator_id` = a.`administrator_id`) AS `rental_contract_count`,
       (SELECT COUNT(*) FROM `payment_record` p  WHERE p.`handled_by_administrator_id` = a.`administrator_id` AND p.`payment_status` = '已支付') AS `paid_payment_count`,
       (SELECT COALESCE(SUM(p.`amount_paid`), 0) FROM `payment_record` p
         WHERE p.`handled_by_administrator_id` = a.`administrator_id` AND p.`payment_status` = '已支付') AS `collected_amount`
FROM `administrator` a
ORDER BY `collected_amount` DESC;

-- 【统计查询 5】本月每日收入统计（示例：2026 年 10 月）
-- 用途：按日统计已支付收入，分解为临停收入与月租收入，用于日结对账。
SELECT DATE(p.`paid_at`) AS `date`,
       SUM(CASE WHEN p.`payment_type` = '临停停车费' THEN p.`amount_paid` ELSE 0 END) AS `temporary_revenue`,
       SUM(CASE WHEN p.`payment_type` = '月租费' THEN p.`amount_paid` ELSE 0 END) AS `rental_revenue`,
       SUM(p.`amount_paid`) AS `daily_revenue`
FROM `payment_record` p
WHERE p.`payment_status` = '已支付'
  AND p.`paid_at` >= '2026-10-01 00:00:00'
  AND p.`paid_at` <  '2026-11-01 00:00:00'
GROUP BY DATE(p.`paid_at`)
ORDER BY `date`;

-- ---------------------------------------------------------------------
-- 4. 样例数据自检：各表记录数
-- ---------------------------------------------------------------------
SELECT '车主' AS `table_name`, COUNT(*) AS `record_count` FROM `vehicle_owner`
UNION ALL SELECT '车辆',     COUNT(*) FROM `vehicle`
UNION ALL SELECT '车位',     COUNT(*) FROM `parking_space`
UNION ALL SELECT '管理员',   COUNT(*) FROM `administrator`
UNION ALL SELECT '收费规则', COUNT(*) FROM `charge_rule`
UNION ALL SELECT '月租合同', COUNT(*) FROM `rental_contract`
UNION ALL SELECT '停车记录', COUNT(*) FROM `parking_record`
UNION ALL SELECT '缴费记录', COUNT(*) FROM `payment_record`;

-- ---------------------------------------------------------------------
-- 5. 约束有效性验证（可选：取消注释逐条执行，预期全部报错）
--    用于课程报告中“有效/无效数据验证结果”的截图证据。
-- ---------------------------------------------------------------------
-- 5.1 唯一约束：重复车牌号           → ERROR 1062 Duplicate entry
-- INSERT INTO `vehicle` (`license_plate`, `vehicle_type`, `owner_id`) VALUES ('京A12345', '小型车', 2);
--
-- 5.2 检查约束：非法车位状态         → ERROR 3819 Check constraint violated
-- INSERT INTO `parking_space` (`space_code`, `area`, `space_type`, `space_status`) VALUES ('C001', 'C 区', '标准', '维护中');
--
-- 5.3 检查约束：月租合同结束日期早于开始日期 → ERROR 3819 Check constraint violated
-- INSERT INTO `rental_contract` (`contract_no`, `vehicle_id`, `start_date`, `end_date`, `monthly_rent`, `handled_by_administrator_id`)
-- VALUES ('HT-2026-999', 1, '2026-12-01', '2026-11-01', 400.00, 1);
--
-- 5.4 检查约束：停车记录同时关联收费规则与月租合同 → ERROR 3819 Check constraint violated
-- INSERT INTO `parking_record` (`vehicle_id`, `parking_space_id`, `parking_type`, `charge_rule_id`, `rental_contract_id`, `entry_time`, `handled_by_administrator_id`)
-- VALUES (1, 2, '临时停车', 1, 1, '2026-10-19 13:00:00', 2);
--
-- 5.5 检查约束：缴费记录未关联任何归属对象 → ERROR 3819 Check constraint violated
-- INSERT INTO `payment_record` (`payment_no`, `payment_type`, `amount_due`, `amount_paid`, `payment_method`, `handled_by_administrator_id`)
-- VALUES ('PAY-TEST-001', '临停停车费', 5.00, 5.00, '现金', 2);
--
-- 5.6 参照完整性：删除被车辆引用的车主 → ERROR 1451 Cannot delete or update a parent row
-- DELETE FROM `vehicle_owner` WHERE `owner_id` = 1;

-- =====================================================================
-- 附：跨记录业务约束说明（本脚本未实现，需应用层事务或触发器校验）
--   1. 同一车辆同一时刻最多一条未出场记录：入场前 SELECT ... FOR UPDATE
--      校验不存在 `vehicle_id = 新记录vehicle_id AND record_status = '在场'` 的记录；
--   2. 同一车位同一时刻最多一条未出场记录：入场前按 `parking_space_id` 同样校验；
--   3. 同一车辆生效合同日期不重叠：签订/续签前校验无
--      `vehicle_id 相同 AND contract_status = '生效' AND 日期区间与新合同相交` 的合同；
--   4. 入场/出场/缴费在同一事务中完成：入场同时把车位改为“占用”，
--      出场补全时间、时长、金额并把车位改为“可用”，退款只更新支付状态。
-- =====================================================================
