SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*
    dbo.sp_GetNextGS1SSCC
    Выдаёт следующий SSCC: строка вида (00) + 18 цифр, через OUTPUT.

    ---------------------------------------------------------------
    Пояснение решений
    ---------------------------------------------------------------

    Почему так с уникальностью
    Не стал делать SELECT текущего значения и потом UPDATE.
    Если две сессии одновременно прочитают LastGS1SSCC = 5, обе
    запишут 6 и отдадут один и тот же номер.

    Здесь следующий номер берётся одним UPDATE: переменная
    заполняется в том же операторе, что и запись в таблицу
    (конструкция SET @Serial = LastGS1SSCC = ...). На строку
    ставится UPDLOCK, вторая сессия просто ждёт. Дублей нет.

    SEQUENCE с CYCLE тоже подошёл бы, но в базе уже есть таблица
    счётчика — работаю с тем, что дано. Отдельный sp_getapplock
    не нужен, строка и так точка сериализации.

    Граница счётчика
    Диапазон 0 .. 999 999 999. В задании сказано, что при верхней
    границе можно сбросить на 0 — так и сделал (CASE, не модуль:
    так проще читать).

    Таблица приходит с LastGS1SSCC = 0. Первый вызов отдаёт 1.
    Ноль выдастся только после оборота, это нормально: 0 входит
    в диапазон, но «последний выданный = 0» в пустой базе значит
    «ещё ничего не выдавали».

    Ошибки
    Если что-то пошло не так — THROW, а не NULL/пустая строка.
    Пустой SSCC хуже исключения: этикетка может уехать на коробку
    без номера.

    @SSCC обнуляю в начале и в CATCH. У OUTPUT-параметра иначе
    могло остаться прошлое значение с клиента.

    Тип NVARCHAR(22): ровно '(00)' + 18 цифр. CHAR дополнил бы
    пробелами, их как раз просили не допускать.
*/

CREATE OR ALTER PROCEDURE dbo.sp_GetNextGS1SSCC
    @SSCC NVARCHAR(22) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @CompanyPrefix CHAR(8) = '54602541'; -- префикс GS1 из задания
    DECLARE @MaxSerial     BIGINT  = 999999999;  -- 9 цифр серийника
    DECLARE @Serial        BIGINT;
    DECLARE @SSCC17        VARCHAR(17);
    DECLARE @Result        NVARCHAR(25);

    SET @SSCC = NULL;

    BEGIN TRY
        /*
            Атомарный инкремент. Без отдельного SELECT:
            @Serial и столбец получают одно и то же новое значение.
        */
        UPDATE dbo.tbl_SSCC_Counter WITH (UPDLOCK, ROWLOCK)
        SET @Serial = LastGS1SSCC =
            CASE
                WHEN LastGS1SSCC >= @MaxSerial THEN 0
                ELSE LastGS1SSCC + 1
            END
        WHERE LastGS1SSCC >= 0
          AND LastGS1SSCC <= @MaxSerial;

        IF @@ROWCOUNT <> 1
        BEGIN
            THROW 50001, 'Не удалось взять следующий номер: в tbl_SSCC_Counter нет одной строки с LastGS1SSCC в диапазоне 0..999999999.', 1;
        END;

        -- 17 цифр без контрольной: префикс 8 знаков + серийник 9 знаков с ведущими нулями
        SET @SSCC17 = @CompanyPrefix
                    + RIGHT(REPLICATE('0', 9) + CAST(@Serial AS VARCHAR(20)), 9);

        SET @Result = dbo.fn_GenerateGS1SSCC(@SSCC17);

        -- функция сама считает контрольную цифру и клеит '(00)'
        IF @Result IS NULL OR LEN(@Result) <> 22
        BEGIN
            THROW 50002, 'fn_GenerateGS1SSCC вернула пустое значение или строку не той длины.', 1;
        END;

        SET @SSCC = @Result;
    END TRY
    BEGIN CATCH
        SET @SSCC = NULL;
        THROW;
    END CATCH;
END
GO
